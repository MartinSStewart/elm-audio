module Audio exposing
    ( elementWithAudio, documentWithAudio, applicationWithAudio
    , AudioCmd, loadAudio, LoadError(..), Source, cmdBatch, cmdNone, sourceDuration
    , Audio, audio, group, silence, audioWithConfig, audioDefaultConfig, PlayAudioConfig, LoopConfig
    , scaleVolume, scaleVolumeAt
    , Model, Msg
    , lamderaFrontendWithAudio
    )

{-|


# Applications

Create an Elm app that supports playing audio.

@docs elementWithAudio, documentWithAudio, applicationWithAudio


# Load audio

Load audio so you can later play it.

@docs AudioCmd, loadAudio, LoadError, Source, cmdBatch, cmdNone, sourceDuration


# Play audio

Define what audio should be playing.

@docs Audio, audio, group, silence, audioWithConfig, audioDefaultConfig, PlayAudioConfig, LoopConfig


# Audio effects

Effects you can apply to `Audio`.

@docs scaleVolume, scaleVolumeAt


# Internal stuff

@docs Model, Msg


# Lamdera stuff

WIP support for Lamdera. Ignore this for now.

@docs lamderaFrontendWithAudio

-}

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Duration exposing (Duration)
import Html exposing (Html)
import Json.Decode as JD
import Json.Encode as JE
import List.Extra as List
import List.Nonempty
import Quantity exposing (Quantity, Rate, Unitless)
import Time
import Url exposing (Url)


{-| -}
type Model userMsg userModel
    = Model (Model_ userMsg userModel)


type alias NodeGroupId =
    Int


type alias Model_ userMsg userModel =
    { audioState : Dict NodeGroupId FlattenedAudio
    , nodeGroupIdCounter : Int
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
    = AudioLoadSuccess { requestId : Int, bufferId : BufferId, duration : Duration }
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

        ( audioState, newNodeGroupIdCounter, json ) =
            diffAudioState model.nodeGroupIdCounter model.audioState (audioFunc newUserModel)

        newModel : Model userMsg userModel
        newModel =
            Model
                { model
                    | audioState = audioState
                    , nodeGroupIdCounter = newNodeGroupIdCounter
                    , userModel = newUserModel
                }

        ( newModel2, audioRequests ) =
            audioCmds |> encodeAudioCmd newModel

        portMessage =
            JE.object
                [ ( "audio", JE.list identity json )
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
        ( audioState, newNodeGroupIdCounter, json ) =
            diffAudioState 0 Dict.empty (audioFunc model)

        initialModel =
            Model
                { audioState = audioState
                , nodeGroupIdCounter = newNodeGroupIdCounter
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
                [ ( "audio", JE.list identity json )
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
                    ( Model model, Cmd.none )


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
                            (JD.field "bufferId" decodeBufferId)
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


type BufferId
    = BufferId Int


encodeBufferId (BufferId bufferId) =
    JE.int bufferId


decodeBufferId =
    JD.int |> JD.map BufferId


updateAudioState :
    ( NodeGroupId, FlattenedAudio )
    -> ( List FlattenedAudio, Dict NodeGroupId FlattenedAudio, List JE.Value )
    -> ( List FlattenedAudio, Dict NodeGroupId FlattenedAudio, List JE.Value )
updateAudioState ( nodeGroupId, audioGroup ) ( flattenedAudio, audioState, json ) =
    let
        validAudio : List ( Int, FlattenedAudio )
        validAudio =
            flattenedAudio
                |> List.indexedMap Tuple.pair
                |> List.filter
                    (\( _, a ) ->
                        (a.source == audioGroup.source)
                            && (a.startTime == audioGroup.startTime)
                            && (a.startAt == audioGroup.startAt)
                    )
    in
    case List.find (\( _, a ) -> a == audioGroup) validAudio of
        Just ( index, _ ) ->
            -- We found a perfect match so nothing needs to change.
            ( List.removeAt index flattenedAudio, audioState, json )

        Nothing ->
            case validAudio of
                ( index, a ) :: _ ->
                    let
                        encodeValue getter encoder =
                            if getter audioGroup == getter a then
                                Nothing

                            else
                                encoder nodeGroupId (getter a) |> Just

                        effects =
                            [ encodeValue .volume encodeSetVolume
                            , encodeValue .loop encodeSetLoopConfig
                            , encodeValue .playbackRate encodeSetPlaybackRate
                            , encodeValue .volumeTimelines encodeSetVolumeAt
                            ]
                                |> List.filterMap identity
                    in
                    -- We found audio that has the same bufferId and startTime but some other settings have changed.
                    ( List.removeAt index flattenedAudio
                    , Dict.insert nodeGroupId a audioState
                    , effects ++ json
                    )

                [] ->
                    -- We didn't find any audio with the same bufferId and startTime so we'll stop this sound.
                    ( flattenedAudio
                    , Dict.remove nodeGroupId audioState
                    , encodeStopSound nodeGroupId :: json
                    )


diffAudioState : Int -> Dict NodeGroupId FlattenedAudio -> Audio -> ( Dict NodeGroupId FlattenedAudio, Int, List JE.Value )
diffAudioState nodeGroupIdCounter audioState newAudio =
    let
        ( newAudioLeft, newAudioState, json2 ) =
            Dict.toList audioState
                |> List.foldl updateAudioState
                    ( flattenAudio newAudio, audioState, [] )

        ( newNodeGroupIdCounter, newAudioState2, json3 ) =
            newAudioLeft
                |> List.foldl
                    (\audioLeft ( counter, audioState_, json_ ) ->
                        ( counter + 1
                        , Dict.insert counter audioLeft audioState_
                        , encodeStartSound counter audioLeft :: json_
                        )
                    )
                    ( nodeGroupIdCounter, newAudioState, json2 )
    in
    ( newAudioState2, newNodeGroupIdCounter, json3 )


encodeStartSound : NodeGroupId -> FlattenedAudio -> JE.Value
encodeStartSound nodeGroupId audio_ =
    JE.object
        [ ( "action", JE.string "startSound" )
        , ( "nodeGroupId", JE.int nodeGroupId )
        , ( "bufferId", audioSourceBufferId audio_.source |> encodeBufferId )
        , ( "startTime", audio_.startTime |> encodeTime )
        , ( "startAt", audio_.startAt |> encodeDuration )
        , ( "volume", JE.float audio_.volume )
        , ( "volumeTimelines", JE.list encodeVolumeTimeline audio_.volumeTimelines )
        , ( "loop", encodeLoopConfig audio_.loop )
        , ( "playbackRate", JE.float audio_.playbackRate )
        ]


encodeTime : Time.Posix -> JE.Value
encodeTime =
    Time.posixToMillis >> JE.int


encodeDuration : Duration -> JE.Value
encodeDuration =
    Duration.inMilliseconds >> JE.float


encodeStopSound : NodeGroupId -> JE.Value
encodeStopSound nodeGroupId =
    JE.object
        [ ( "action", JE.string "stopSound" )
        , ( "nodeGroupId", JE.int nodeGroupId )
        ]


encodeSetVolume : NodeGroupId -> Float -> JE.Value
encodeSetVolume nodeGroupId volume =
    JE.object
        [ ( "nodeGroupId", JE.int nodeGroupId )
        , ( "action", JE.string "setVolume" )
        , ( "volume", JE.float volume )
        ]


encodeSetLoopConfig : NodeGroupId -> Maybe LoopConfig -> JE.Value
encodeSetLoopConfig nodeGroupId loop =
    JE.object
        [ ( "nodeGroupId", JE.int nodeGroupId )
        , ( "action", JE.string "setLoopConfig" )
        , ( "loop", encodeLoopConfig loop )
        ]


encodeSetPlaybackRate : NodeGroupId -> Float -> JE.Value
encodeSetPlaybackRate nodeGroupId playbackRate =
    JE.object
        [ ( "nodeGroupId", JE.int nodeGroupId )
        , ( "action", JE.string "setPlaybackRate" )
        , ( "playbackRate", JE.float playbackRate )
        ]


type alias VolumeTimeline =
    List.Nonempty.Nonempty ( Time.Posix, Float )


encodeSetVolumeAt : NodeGroupId -> List VolumeTimeline -> JE.Value
encodeSetVolumeAt nodeGroupId volumeTimelines =
    JE.object
        [ ( "nodeGroupId", JE.int nodeGroupId )
        , ( "action", JE.string "setVolumeAt" )
        , ( "volumeAt", JE.list encodeVolumeTimeline volumeTimelines )
        ]


encodeVolumeTimeline : VolumeTimeline -> JE.Value
encodeVolumeTimeline volumeTimeline =
    volumeTimeline
        |> List.Nonempty.toList
        |> JE.list
            (\( time, volume ) ->
                JE.object
                    [ ( "time", encodeTime time )
                    , ( "volume", JE.float volume )
                    ]
            )


encodeLoopConfig : Maybe LoopConfig -> JE.Value
encodeLoopConfig maybeLoop =
    case maybeLoop of
        Just loop ->
            JE.object
                [ ( "loopStart", encodeDuration loop.loopStart )
                , ( "loopEnd", encodeDuration loop.loopEnd )
                ]

        Nothing ->
            JE.null


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


type alias FlattenedAudio =
    { source : Source
    , startTime : Time.Posix
    , startAt : Duration
    , volume : Float
    , volumeTimelines : List (List.Nonempty.Nonempty ( Time.Posix, Float ))
    , loop : Maybe LoopConfig
    , playbackRate : Float
    }


flattenAudio : Audio -> List FlattenedAudio
flattenAudio audio_ =
    case audio_ of
        Group group_ ->
            group_ |> List.map flattenAudio |> List.concat

        BasicAudio { source, startTime, settings } ->
            [ { source = source
              , startTime = startTime
              , startAt = settings.startAt
              , volume = 1
              , volumeTimelines = []
              , loop = settings.loop
              , playbackRate = settings.playbackRate
              }
            ]

        Effect effect ->
            case effect.effectType of
                ScaleVolume scaleVolume_ ->
                    List.map
                        (\a -> { a | volume = scaleVolume_.scaleBy * a.volume })
                        (flattenAudio effect.audio)

                ScaleVolumeAt { volumeAt } ->
                    List.map
                        (\a -> { a | volumeTimelines = volumeAt :: a.volumeTimelines })
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
    = ScaleVolume { scaleBy : Float }
    | ScaleVolumeAt { volumeAt : List.Nonempty.Nonempty ( Time.Posix, Float ) }


{-| -}
type Source
    = File { bufferId : BufferId, duration : Duration }


{-| Get how long an audio source plays for.
-}
sourceDuration : Source -> Duration
sourceDuration (File source) =
    source.duration


audioSourceBufferId (File audioSource) =
    audioSource.bufferId


{-| Extra settings when playing audio from a file.
-}
type alias PlayAudioConfig =
    { loop : Maybe LoopConfig
    , playbackRate : Float
    , startAt : Duration
    }


{-| Default config used for `audioWithConfig`.
-}
audioDefaultConfig : PlayAudioConfig
audioDefaultConfig =
    { loop = Nothing
    , playbackRate = 1
    , startAt = Quantity.zero
    }


{-| Control how audio loops. `loopEnd` defines where (relative to the start of the audio) the audio should loop and `loopStart` where it should loop to.

    -- Here we have a song that plays an intro once and then loops between the 10 second point and the end of the song.
    let
        default =
            Audio.audioDefaultConfig

        songLength =
            Audio.sourceDuration coolBackgroundMusic
    in
    audioWithConfig
        { default | loop = Just { loopStart = Duration.seconds 10, loopEnd = songLength } }
        coolBackgroundMusic
        startTime

-}
type alias LoopConfig =
    { loopStart : Duration, loopEnd : Duration }


{-| Play audio from an audio source at a given time. This is the same as using `audioWithConfig audioDefaultConfig`.
-}
audio : Source -> Time.Posix -> Audio
audio source startTime =
    audioWithConfig audioDefaultConfig source startTime


{-| Play audio from an audio source at a given time with config.
-}
audioWithConfig : PlayAudioConfig -> Source -> Time.Posix -> Audio
audioWithConfig audioSettings source startTime =
    BasicAudio { source = source, startTime = startTime, settings = audioSettings }


{-| Scale how loud a given `Audio` is. If the the volume is less than 0, 0 will be used instead.
-}
scaleVolume : Float -> Audio -> Audio
scaleVolume scaleBy audio_ =
    Effect { effectType = ScaleVolume { scaleBy = max 0 scaleBy }, audio = audio_ }


{-| Scale how loud a given `Audio` is given points in time. The volume will transition linearly between those points.
-}
scaleVolumeAt : VolumeTimeline -> Audio -> Audio
scaleVolumeAt volumeAt audio_ =
    Effect
        { effectType =
            ScaleVolumeAt
                { volumeAt =
                    volumeAt
                        |> List.Nonempty.map (Tuple.mapSecond (max 0))
                        |> List.Nonempty.sortBy (Tuple.first >> Time.posixToMillis)
                }
        , audio = audio_
        }


{-| Combine multiple `Audio`s into a single `Audio`.
-}
group : List Audio -> Audio
group audios =
    Group audios


{-| The sound of no sound at all.
-}
silence : Audio
silence =
    group []


{-| Possible errors we can get when loading audio files.
-}
type LoadError
    = MediaDecodeAudioDataUnknownContentType
    | NetworkError


{-| Load audio from a url.
-}
loadAudio : (Result LoadError Source -> msg) -> String -> AudioCmd msg
loadAudio userMsg url =
    AudioLoadRequest { userMsg = userMsg, audioUrl = url }
