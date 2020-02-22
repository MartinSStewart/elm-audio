module Audio exposing
    ( Audio
    , AudioCmd
    , LoadError(..)
    , Model
    , Msg
    , Source(..)
    , applicationWithAudio
    , audio
    , cmdBatch
    , cmdNone
    , documentWithAudio
    , elementWithAudio
    , group
    , loadAudio
    , scaleVolume
    , scaleVolumeAt
    , silence
    , sourceDuration
    )

{- Basic idea for an audio package.

   The foundational idea here is that:

   1. Audio is like a view function.
   It's takes a model and returns a collection of sounds that should be playing.
   If a sound effect stops being returned from our audio function then it stops playing.
   2. It should be configurable enough that the user doesn't need to say what sounds should be playing 60 times per second.
   For example, `audio` lets us choose when a sound effect should play rather than needing to wait until that exact moment.

   Example usage:

   import Audio exposing (..)

   type alias Model =
       { damageSoundEffect : AudioSource
       , playerLastDamaged : Maybe Time.Posix
       , backgroundMusic : AudioSource
       }

   damageSoundEffectDuration = 2000

   audio : Model -> Audio
   audio model =
        group
            [ audio model.backgroundMusic (MillisecondsSinceAppStart 0) Nothing 0
            , case model.playerLastDamaged of
                Just playerLastDamaged ->
                    audio model.damageSoundEffect (AbsoluteTime playerLastDamaged) damageSoundEffectDuration 0

                Nothing ->
                    silence
            ]

    main =
        elementWithAudio
            { init = Debug.todo ""
            , view = Debug.todo ""
            , update = Debug.todo ""
            , subscriptions = Debug.todo ""
            , audio = audio
            }

-}

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Duration exposing (Duration)
import Html exposing (Html)
import Json.Decode as JD
import Json.Encode as JE
import List.Extra as List
import Quantity exposing (Quantity, Rate, Unitless)
import Time
import Url exposing (Url)


{-| -}
type Model userMsg userModel
    = Model (Model_ userMsg userModel)


type alias Model_ userMsg userModel =
    { audioState : Audio
    , userModel : userModel
    , requestCount : Int
    , pendingRequests : Dict Int (AudioLoadRequest_ userMsg)
    , samplesPerSecond : Maybe Int
    }


{-| -}
type Msg userMsg
    = FromJSMsg FromJSMsg
    | UserMsg userMsg


type FromJSMsg
    = AudioLoadSuccess { requestId : Int, bufferId : Int, duration : Duration }
    | AudioLoadFailed { requestId : Int, error : LoadError }
    | InitAudioContext { samplesPerSecond : Int }
    | JsonParseError { error : String }


type alias AudioLoadRequest_ userMsg =
    { userMsg : Result LoadError Source -> userMsg, audioUrl : String }


{-| An audio command.
-}
type AudioCmd userMsg
    = AudioLoadRequest (AudioLoadRequest_ userMsg)
    | AudioCmdGroup (List (AudioCmd userMsg))


{-| Combine multiple commands into a single command. Conceptually the same as Cmd.batch.
-}
cmdBatch : List (AudioCmd userMsg) -> AudioCmd userMsg
cmdBatch audioCmds =
    AudioCmdGroup audioCmds


{-| A command that does nothing. Conceptually the same as Cmd.none.
-}
cmdNone : AudioCmd msg
cmdNone =
    AudioCmdGroup []


{-| Ports that allows this package to communicate with the JS portion of the package.
-}
type alias Ports msg =
    { toJS : JE.Value -> Cmd (Msg msg), fromJS : (JD.Value -> Msg msg) -> Sub (Msg msg) }


getUserModel : Model userMsg userModel -> userModel
getUserModel (Model model) =
    model.userModel


{-| Browser.element but with the ability to play sounds.
-}
elementWithAudio :
    { init : flags -> ( model, Cmd msg, AudioCmd msg )
    , view : model -> Html msg
    , update : msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : model -> Sub msg
    , audio : model -> Audio
    , audioPort : Ports msg
    }
    -> Program flags (Model msg model) (Msg msg)
elementWithAudio app =
    { init = app.init >> initHelper app.audioPort.toJS app.audio
    , view = getUserModel >> app.view >> Html.map UserMsg
    , update = update app
    , subscriptions = subscriptions app
    }
        |> Browser.element


{-| Browser.document but with the ability to play sounds.
-}
documentWithAudio :
    { init : flags -> ( model, Cmd msg, AudioCmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : model -> Sub msg
    , audio : model -> Audio
    , audioPort : Ports msg
    }
    -> Program flags (Model msg model) (Msg msg)
documentWithAudio app =
    { init = app.init >> initHelper app.audioPort.toJS app.audio
    , view =
        \model ->
            let
                { title, body } =
                    app.view (getUserModel model)
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update = update app
    , subscriptions = subscriptions app
    }
        |> Browser.document


{-| Browser.application but with the ability to play sounds.
-}
applicationWithAudio :
    { init : flags -> Url -> Key -> ( model, Cmd msg, AudioCmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : model -> Sub msg
    , onUrlRequest : Browser.UrlRequest -> msg
    , onUrlChange : Url -> msg
    , audio : model -> Audio
    , audioPort : Ports msg
    }
    -> Program flags (Model msg model) (Msg msg)
applicationWithAudio app =
    { init = \flags url key -> app.init flags url key |> initHelper app.audioPort.toJS app.audio
    , view =
        \model ->
            let
                { title, body } =
                    app.view (getUserModel model)
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update = update app
    , subscriptions = subscriptions app
    , onUrlRequest = app.onUrlRequest >> UserMsg
    , onUrlChange = app.onUrlChange >> UserMsg
    }
        |> Browser.application


{-| Lamdera.frontend but with the ability to play sounds (highly experimental, just ignore this for now).
-}
lamderaFrontendWithAudio :
    { init : Url.Url -> Browser.Navigation.Key -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , view : model -> Browser.Document frontendMsg
    , update : frontendMsg -> model -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , updateFromBackend : toFrontend -> model -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , subscriptions : model -> Sub frontendMsg
    , onUrlRequest : Browser.UrlRequest -> frontendMsg
    , onUrlChange : Url -> frontendMsg
    , audio : model -> Audio
    , audioPort : Ports frontendMsg
    }
    ->
        { init : Url.Url -> Browser.Navigation.Key -> ( Model frontendMsg model, Cmd (Msg frontendMsg) )
        , view : Model frontendMsg model -> Browser.Document (Msg frontendMsg)
        , update : Msg frontendMsg -> Model frontendMsg model -> ( Model frontendMsg model, Cmd (Msg frontendMsg) )
        , updateFromBackend : toFrontend -> Model frontendMsg model -> ( Model frontendMsg model, Cmd (Msg frontendMsg) )
        , subscriptions : Model frontendMsg model -> Sub (Msg frontendMsg)
        , onUrlRequest : Browser.UrlRequest -> Msg frontendMsg
        , onUrlChange : Url -> Msg frontendMsg
        }
lamderaFrontendWithAudio app =
    { init = \url key -> initHelper app.audioPort.toJS app.audio (app.init url key)
    , view =
        \model ->
            let
                { title, body } =
                    app.view (getUserModel model)
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update = update app
    , updateFromBackend =
        \toFrontend model ->
            updateHelper app.audioPort.toJS app.audio (app.updateFromBackend toFrontend) model
    , subscriptions = subscriptions app
    , onUrlRequest = app.onUrlRequest >> UserMsg
    , onUrlChange = app.onUrlChange >> UserMsg
    }


updateHelper :
    (JD.Value -> Cmd (Msg userMsg))
    -> (userModel -> Audio)
    -> (userModel -> ( userModel, Cmd userMsg, AudioCmd userMsg ))
    -> Model userMsg userModel
    -> ( Model userMsg userModel, Cmd (Msg userMsg) )
updateHelper audioPort audioFunc userUpdate (Model model) =
    let
        ( newUserModel, userCmd, audioCmds ) =
            userUpdate model.userModel

        newAudioState =
            audioFunc newUserModel

        diff =
            diffAudioState model.audioState newAudioState

        newModel : Model userMsg userModel
        newModel =
            Model { model | audioState = newAudioState, userModel = newUserModel }

        ( newModel2, audioRequests ) =
            audioCmds |> encodeAudioCmd newModel

        portMessage =
            JE.object
                [ ( "audio", diff )
                , ( "audioCmds", audioRequests )
                ]
    in
    ( newModel2
    , Cmd.batch [ Cmd.map UserMsg userCmd, audioPort portMessage ]
    )


initHelper :
    (JD.Value -> Cmd (Msg userMsg))
    -> (model -> Audio)
    -> ( model, Cmd userMsg, AudioCmd userMsg )
    -> ( Model userMsg model, Cmd (Msg userMsg) )
initHelper audioPort audioFunc ( model, cmds, audioCmds ) =
    let
        newAudioState : Audio
        newAudioState =
            audioFunc model

        diff =
            diffAudioState silence newAudioState

        initialModel =
            Model
                { audioState = newAudioState
                , userModel = model
                , requestCount = 0
                , pendingRequests = Dict.empty
                , samplesPerSecond = Nothing
                }

        ( initialModel2, audioRequests ) =
            audioCmds |> encodeAudioCmd initialModel

        portMessage : JE.Value
        portMessage =
            JE.object
                [ ( "audio", diff )
                , ( "audioCmds", audioRequests )
                ]
    in
    ( initialModel2
    , Cmd.batch [ Cmd.map UserMsg cmds, audioPort portMessage ]
    )


update :
    { a
        | audioPort : Ports userMsg
        , audio : userModel -> Audio
        , update : userMsg -> userModel -> ( userModel, Cmd userMsg, AudioCmd userMsg )
    }
    -> Msg userMsg
    -> Model userMsg userModel
    -> ( Model userMsg userModel, Cmd (Msg userMsg) )
update app msg (Model model) =
    case msg of
        UserMsg userMsg ->
            updateHelper app.audioPort.toJS app.audio (app.update userMsg) (Model model)

        FromJSMsg response ->
            case response of
                AudioLoadSuccess { requestId, bufferId, duration } ->
                    case Dict.get requestId model.pendingRequests of
                        Just pendingRequest ->
                            let
                                userMsg =
                                    { bufferId = bufferId
                                    , duration = duration
                                    }
                                        |> File
                                        |> Ok
                                        |> pendingRequest.userMsg
                            in
                            { model | pendingRequests = Dict.remove requestId model.pendingRequests }
                                |> Model
                                |> updateHelper
                                    app.audioPort.toJS
                                    app.audio
                                    (app.update userMsg)

                        Nothing ->
                            ( Model model, Cmd.none )

                AudioLoadFailed { requestId, error } ->
                    case Dict.get requestId model.pendingRequests of
                        Just pendingRequest ->
                            let
                                userMsg =
                                    Err error |> pendingRequest.userMsg
                            in
                            { model | pendingRequests = Dict.remove requestId model.pendingRequests }
                                |> Model
                                |> updateHelper
                                    app.audioPort.toJS
                                    app.audio
                                    (app.update userMsg)

                        Nothing ->
                            ( Model model, Cmd.none )

                InitAudioContext { samplesPerSecond } ->
                    ( Model { model | samplesPerSecond = Just samplesPerSecond }, Cmd.none )

                JsonParseError { error } ->
                    Debug.todo error


subscriptions :
    { a | subscriptions : userModel -> Sub userMsg, audioPort : Ports userMsg }
    -> Model userMsg userModel
    -> Sub (Msg userMsg)
subscriptions app (Model model) =
    Sub.batch [ app.subscriptions model.userModel |> Sub.map UserMsg, app.audioPort.fromJS fromJSPortSub ]


decodeLoadError =
    JD.string
        |> JD.andThen
            (\value ->
                case value of
                    "NetworkError" ->
                        JD.succeed NetworkError

                    "MediaDecodeAudioDataUnknownContentType" ->
                        JD.succeed MediaDecodeAudioDataUnknownContentType

                    _ ->
                        JD.fail "Unknown load error"
            )


decodeFromJSMsg =
    JD.field "type" JD.int
        |> JD.andThen
            (\value ->
                case value of
                    0 ->
                        JD.map2 (\requestId error -> AudioLoadFailed { requestId = requestId, error = error })
                            (JD.field "requestId" JD.int)
                            (JD.field "error" decodeLoadError)

                    1 ->
                        JD.map3
                            (\requestId bufferId duration ->
                                AudioLoadSuccess
                                    { requestId = requestId
                                    , bufferId = bufferId
                                    , duration = Duration.seconds duration
                                    }
                            )
                            (JD.field "requestId" JD.int)
                            (JD.field "bufferId" JD.int)
                            (JD.field "durationInSeconds" JD.float)

                    2 ->
                        JD.map (\samplesPerSecond -> InitAudioContext { samplesPerSecond = samplesPerSecond })
                            (JD.field "samplesPerSecond" JD.int)

                    _ ->
                        JsonParseError { error = "Type " ++ String.fromInt value ++ " not handled." } |> JD.succeed
            )


fromJSPortSub : JD.Value -> Msg userMsg
fromJSPortSub json =
    case JD.decodeValue decodeFromJSMsg json of
        Ok value ->
            FromJSMsg value

        Err error ->
            FromJSMsg (JsonParseError { error = JD.errorToString error })


diffAudioState : Audio -> Audio -> JE.Value
diffAudioState oldAudio newAudio =
    let
        flattenedOldAudio =
            flattenAudio oldAudio

        flattenedNewAudio : List FlattenedAudio
        flattenedNewAudio =
            flattenAudio newAudio

        getDict =
            List.gatherEqualsBy (\audio_ -> audioSourceBufferId audio_.source)
                >> List.map (\( audio_, rest ) -> ( audioSourceBufferId audio_.source, audio_ :: rest ))
                >> Dict.fromList
    in
    Dict.merge
        (\bufferId oldValues result -> diffLists bufferId oldValues [] ++ result)
        (\bufferId oldValues newValues result -> diffLists bufferId oldValues newValues ++ result)
        (\bufferId newValues result -> diffLists bufferId [] newValues ++ result)
        (getDict flattenedOldAudio)
        (getDict flattenedNewAudio)
        []
        |> JE.list identity


diffLists : Int -> List FlattenedAudio -> List FlattenedAudio -> List JE.Value
diffLists bufferId oldValues newValues =
    if oldValues == newValues then
        []

    else
        [ oldValues
            |> List.map
                (\oldValue ->
                    JE.object
                        [ ( "bufferId", JE.int bufferId )
                        , ( "action", JE.string "stopSound" )
                        ]
                )
        , newValues
            |> List.map
                (\newValue ->
                    JE.object
                        [ ( "bufferId", JE.int bufferId )
                        , ( "action", JE.string "startSound" )
                        , ( "startTime", JE.int (Time.posixToMillis newValue.startTime) )
                        ]
                )
        ]
            |> List.concat


flattenAudioCmd : AudioCmd msg -> List (AudioLoadRequest_ msg)
flattenAudioCmd audioCmd =
    case audioCmd of
        AudioLoadRequest data ->
            [ data ]

        AudioCmdGroup list ->
            List.map flattenAudioCmd list |> List.concat


encodeAudioCmd : Model userMsg userModel -> AudioCmd userMsg -> ( Model userMsg userModel, JE.Value )
encodeAudioCmd (Model model) audioCmd =
    let
        flattenedAudioCmd : List (AudioLoadRequest_ userMsg)
        flattenedAudioCmd =
            flattenAudioCmd audioCmd

        newPendingRequests : List ( Int, AudioLoadRequest_ userMsg )
        newPendingRequests =
            flattenedAudioCmd |> List.indexedMap Tuple.pair
    in
    ( { model
        | requestCount = model.requestCount + List.length flattenedAudioCmd
        , pendingRequests = Dict.union model.pendingRequests (Dict.fromList newPendingRequests)
      }
        |> Model
    , newPendingRequests
        |> List.map (\( index, value ) -> encodeAudioLoadRequest (model.requestCount + index) value)
        |> JE.list identity
    )


encodeAudioLoadRequest : Int -> AudioLoadRequest_ msg -> JE.Value
encodeAudioLoadRequest index audioLoad =
    JE.object
        [ ( "audioUrl", JE.string audioLoad.audioUrl )
        , ( "requestId", JE.int index )
        ]


encodeFlattenedAudio : FlattenedAudio -> JE.Value
encodeFlattenedAudio flattenedAudio =
    JE.object
        [ ( "source", encodeAudioSource flattenedAudio.source )
        , ( "startTime", JE.int (Time.posixToMillis flattenedAudio.startTime) )
        , ( "endTime"
          , case flattenedAudio.endTime of
                Just endTime ->
                    JE.float (Duration.inMilliseconds endTime)

                Nothing ->
                    JE.null
          )
        , ( "startAt", JE.float (Duration.inMilliseconds flattenedAudio.startAt) )
        , ( "volume"
          , flattenedAudio.volume |> Quantity.sortBy .startTime |> JE.list encodeVolumeEffect
          )
        ]


encodeVolumeEffect : { startTime : Duration, scaleBy : Float } -> JE.Value
encodeVolumeEffect { startTime, scaleBy } =
    JE.object
        [ ( "startTime", JE.float (Duration.inMilliseconds startTime) )
        , ( "scaleBy", JE.float scaleBy )
        ]


encodePlaybackRateEffect : { startTime : Duration, scaleBy : Float } -> JE.Value
encodePlaybackRateEffect { startTime, scaleBy } =
    JE.object
        [ ( "startTime", JE.float (Duration.inMilliseconds startTime) )
        , ( "scaleBy", JE.float scaleBy )
        ]


encodeAudioSource : Source -> JE.Value
encodeAudioSource audioSource =
    case audioSource of
        File audioFile ->
            JE.object
                [ ( "type", JE.int 0 )
                , ( "bufferId", JE.int audioFile.bufferId )
                ]


type alias FlattenedAudio =
    { source : Source
    , startTime : Time.Posix
    , endTime : Maybe Duration
    , startAt : Duration
    , volume : List { scaleBy : Float, startTime : Duration }
    }


flattenAudio : Audio -> List FlattenedAudio
flattenAudio audio_ =
    case audio_ of
        Group group_ ->
            group_ |> List.map flattenAudio |> List.concat

        BasicAudio { source, startTime, settings } ->
            [ { source = source
              , startTime = startTime
              , endTime = settings.endTime
              , startAt = settings.offset
              , volume = []
              }
            ]

        Effect effect ->
            case effect.effectType of
                ScaleVolume scaleVolume_ ->
                    List.map
                        (\{ source, startTime, endTime, startAt, volume } ->
                            { source = source
                            , startTime = startTime
                            , endTime = endTime
                            , startAt = startAt
                            , volume = scaleVolume_ :: volume
                            }
                        )
                        (flattenAudio effect.audio)


{-| Some kind of sound we want to play. To create `Audio` start with `audio`.
-}
type Audio
    = Group (List Audio)
    | BasicAudio { source : Source, startTime : Time.Posix, settings : PlayAudioConfig }
    | Effect { effectType : EffectType, audio : Audio }


{-| An effect we can apply to our sound such as changing the volume.
-}
type EffectType
    = ScaleVolume { scaleBy : Float, startTime : Duration }


type Source
    = File { bufferId : Int, duration : Duration }


{-| How long an audio source plays for.
-}
sourceDuration : Source -> Duration
sourceDuration (File source) =
    source.duration


audioSourceBufferId (File audioSource) =
    audioSource.bufferId


{-| Extra settings when playing audio from a file.
-}
type alias PlayAudioConfig =
    { endTime : Maybe Duration
    , offset : Duration
    , loop : Maybe { loopStart : Duration, loopEnd : Duration }
    }


{-| Play audio from an audio source at a given time.
-}
audio : Source -> Time.Posix -> Audio
audio source startTime =
    audioWithConfig source startTime { endTime = Nothing, offset = Quantity.zero, loop = Nothing }


{-| Play audio from an audio source at a given time with config.
-}
audioWithConfig : Source -> Time.Posix -> PlayAudioConfig -> Audio
audioWithConfig source startTime audioSettings =
    BasicAudio { source = source, startTime = startTime, settings = audioSettings }


scaleVolume : Float -> Audio -> Audio
scaleVolume scaleBy audio_ =
    Effect { effectType = ScaleVolume { scaleBy = scaleBy, startTime = Quantity.zero }, audio = audio_ }


scaleVolumeAt : Float -> Duration -> Audio -> Audio
scaleVolumeAt scaleBy startTime audio_ =
    Effect { effectType = ScaleVolume { scaleBy = scaleBy, startTime = startTime }, audio = audio_ }


group : List Audio -> Audio
group audios =
    Group audios


{-| The sound of no sound at all.
-}
silence : Audio
silence =
    group []


type LoadError
    = MediaDecodeAudioDataUnknownContentType
    | NetworkError


{-| Load audio from a url.
-}
loadAudio : (Result LoadError Source -> msg) -> String -> AudioCmd msg
loadAudio userMsg url =
    AudioLoadRequest { userMsg = userMsg, audioUrl = url }
