module Audio exposing
    ( Audio
    , AudioSource
    , Error(..)
    , applicationWithAudio
    , audio
    , documentWithAudio
    , elementWithAudio
    , group
    , loadAudio
    , scalePlaybackRateAt
    , scaleVolume
    , scaleVolumeAt
    , sineWave
    )

{- Basic idea for an audio package.

   The foundational idea here is that:

   1. Audio is like a view function.
   It's takes a modelnd returns a collection of sounds that should be playing.
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
import Duration exposing (Duration)
import Html exposing (Html)
import Json.Encode
import Quantity
import Set exposing (Set)
import Task exposing (Task)
import Time
import Url exposing (Url)


type alias Model a =
    { audioState : Audio
    , userModel : a
    }


type Msg a
    = AudioLoad
    | UserMsg a


sandboxWithAudio :
    { init : model
    , view : model -> Html msg
    , update : msg -> model -> model
    , audio : model -> Audio
    , audioPort : Json.Encode.Value -> Cmd msg
    }
    -> Program () (Model model) (Msg msg)
sandboxWithAudio app =
    { init = \_ -> initHelper app.audioPort app.audio ( app.init, Cmd.none )
    , view = .userModel >> app.view >> Html.map UserMsg
    , update =
        \msg model ->
            case msg of
                UserMsg userMsg ->
                    let
                        newUserModel =
                            app.update userMsg model.userModel

                        newAudioState =
                            app.audio newUserModel

                        diff =
                            diffAudioState model.audioState newAudioState |> app.audioPort
                    in
                    ( { audioState = newAudioState, userModel = newUserModel }
                    , Cmd.map UserMsg diff
                    )

                AudioLoad ->
                    Debug.todo ""
    , subscriptions = always Sub.none
    }
        |> Browser.element


elementWithAudio :
    { init : flags -> ( model, Cmd msg )
    , view : model -> Html msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , audio : model -> Audio
    , audioPort : Json.Encode.Value -> Cmd msg
    }
    -> Program flags (Model model) (Msg msg)
elementWithAudio app =
    { init = app.init >> initHelper app.audioPort app.audio
    , view = .userModel >> app.view >> Html.map UserMsg
    , update =
        \msg model ->
            case msg of
                UserMsg userMsg ->
                    updateHelper app.audioPort app.audio (app.update userMsg) model

                AudioLoad ->
                    Debug.todo ""
    , subscriptions = \model -> app.subscriptions model.userModel |> Sub.map UserMsg
    }
        |> Browser.element


documentWithAudio :
    { init : flags -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , audio : model -> Audio
    , audioPort : Json.Encode.Value -> Cmd msg
    }
    -> Program flags (Model model) (Msg msg)
documentWithAudio app =
    { init = app.init >> initHelper app.audioPort app.audio
    , view =
        \model ->
            let
                { title, body } =
                    app.view model.userModel
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update =
        \msg model ->
            case msg of
                UserMsg userMsg ->
                    updateHelper app.audioPort app.audio (app.update userMsg) model

                AudioLoad ->
                    Debug.todo ""
    , subscriptions = \model -> app.subscriptions model.userModel |> Sub.map UserMsg
    }
        |> Browser.document


applicationWithAudio :
    { init : flags -> Url -> Key -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , onUrlRequest : Browser.UrlRequest -> msg
    , onUrlChange : Url -> msg
    , audio : model -> Audio
    , audioPort : Json.Encode.Value -> Cmd msg
    }
    -> Program flags (Model model) (Msg msg)
applicationWithAudio app =
    { init = \flags url key -> initHelper app.audioPort app.audio (app.init flags url key)
    , view =
        \model ->
            let
                { title, body } =
                    app.view model.userModel
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update =
        \msg model ->
            case msg of
                UserMsg userMsg ->
                    updateHelper app.audioPort app.audio (app.update userMsg) model

                AudioLoad ->
                    Debug.todo ""
    , subscriptions = \model -> app.subscriptions model.userModel |> Sub.map UserMsg
    , onUrlRequest = app.onUrlRequest >> UserMsg
    , onUrlChange = app.onUrlChange >> UserMsg
    }
        |> Browser.application


lamderaFrontendWithAudio :
    { init : Url.Url -> Browser.Navigation.Key -> ( model, Cmd frontendMsg )
    , view : model -> Browser.Document frontendMsg
    , update : frontendMsg -> model -> ( model, Cmd frontendMsg )
    , updateFromBackend : toFrontend -> model -> ( model, Cmd frontendMsg )
    , subscriptions : model -> Sub frontendMsg
    , onUrlRequest : Browser.UrlRequest -> frontendMsg
    , onUrlChange : Url -> frontendMsg
    , audio : model -> Audio
    , audioPort : Json.Encode.Value -> Cmd frontendMsg
    }
    ->
        { init : Url.Url -> Browser.Navigation.Key -> ( Model model, Cmd (Msg frontendMsg) )
        , view : Model model -> Browser.Document (Msg frontendMsg)
        , update : Msg frontendMsg -> Model model -> ( Model model, Cmd (Msg frontendMsg) )
        , updateFromBackend : toFrontend -> Model model -> ( Model model, Cmd (Msg frontendMsg) )
        , subscriptions : Model model -> Sub (Msg frontendMsg)
        , onUrlRequest : Browser.UrlRequest -> Msg frontendMsg
        , onUrlChange : Url -> Msg frontendMsg
        }
lamderaFrontendWithAudio app =
    { init =
        \url key -> initHelper app.audioPort app.audio (app.init url key)
    , view =
        \model ->
            let
                { title, body } =
                    app.view model.userModel
            in
            { title = title
            , body = body |> List.map (Html.map UserMsg)
            }
    , update =
        \msg model ->
            case msg of
                UserMsg userMsg ->
                    updateHelper app.audioPort app.audio (app.update userMsg) model

                AudioLoad ->
                    Debug.todo ""
    , updateFromBackend =
        \toFrontend model ->
            updateHelper app.audioPort app.audio (app.updateFromBackend toFrontend) model
    , subscriptions = \model -> app.subscriptions model.userModel |> Sub.map UserMsg
    , onUrlRequest = app.onUrlRequest >> UserMsg
    , onUrlChange = app.onUrlChange >> UserMsg
    }


updateHelper :
    (Json.Encode.Value -> Cmd msg)
    -> (model -> Audio)
    -> (model -> ( model, Cmd msg ))
    -> Model model
    -> ( Model model, Cmd (Msg msg) )
updateHelper audioPort audioFunc userUpdate model =
    let
        ( newUserModel, userCmd ) =
            userUpdate model.userModel

        newAudioState =
            audioFunc newUserModel

        diff =
            diffAudioState model.audioState newAudioState |> audioPort
    in
    ( { audioState = newAudioState, userModel = newUserModel }
    , Cmd.batch [ Cmd.map UserMsg userCmd, Cmd.map UserMsg diff ]
    )


initHelper audioPort audioFunc userInit =
    let
        ( newUserModel, userCmd ) =
            userInit

        newAudioState =
            audioFunc newUserModel

        diff =
            diffAudioState silence newAudioState |> audioPort
    in
    ( { audioState = newAudioState, userModel = newUserModel }
    , Cmd.batch [ Cmd.map UserMsg userCmd, Cmd.map UserMsg diff ]
    )


diffAudioState : Audio -> Audio -> Json.Encode.Value
diffAudioState oldAudio newAudio =
    let
        flattenedOldAudio =
            flattenAudio oldAudio

        flattenedNewAudio =
            flattenAudio newAudio

        a =
            0
    in
    Debug.todo ""


type alias FlattenedAudio =
    { source : AudioSource
    , startTime : Duration
    , endTime : Maybe Duration
    , startAt : Float
    , volume : List { scaleBy : Float, startTime : Duration }
    , playbackRate : List { scaleBy : Float, startTime : Duration }
    }


flattenAudio : Audio -> List FlattenedAudio
flattenAudio audio_ =
    case audio_ of
        Group group_ ->
            group_ |> List.map flattenAudio |> List.concat

        BasicAudio { source, startTime, endTime, startAt } ->
            [ { source = source
              , startTime = startTime
              , endTime = endTime
              , startAt = startAt
              , volume = []
              , playbackRate = []
              }
            ]

        Effect effect ->
            case effect.effectType of
                ScaleVolume scaleVolume_ ->
                    List.map
                        (\{ source, startTime, endTime, startAt, volume, playbackRate } ->
                            { source = source
                            , startTime = startTime
                            , endTime = endTime
                            , startAt = startAt
                            , volume = scaleVolume_ :: volume
                            , playbackRate = playbackRate
                            }
                        )
                        (flattenAudio effect.audio)

                ScalePlaybackRate scalePlaybackRate ->
                    List.map
                        (\{ source, startTime, endTime, startAt, volume, playbackRate } ->
                            { source = source
                            , startTime = startTime
                            , endTime = endTime
                            , startAt = startAt
                            , volume = volume
                            , playbackRate = scalePlaybackRate :: playbackRate
                            }
                        )
                        (flattenAudio effect.audio)


type Audio
    = Group (List Audio)
    | BasicAudio { source : AudioSource, startTime : Duration, endTime : Maybe Duration, startAt : Float }
    | Effect { effectType : EffectType, audio : Audio }


type EffectType
    = ScaleVolume { scaleBy : Float, startTime : Duration }
    | ScalePlaybackRate { scaleBy : Float, startTime : Duration }


type AudioSource
    = AudioFile String
    | SineWave { frequency : Float }


audio : AudioSource -> Duration -> Maybe Duration -> Float -> Audio
audio source startTime endTime offset =
    BasicAudio { source = source, startTime = startTime, endTime = endTime, startAt = offset }


scaleVolume : Float -> Audio -> Audio
scaleVolume scaleBy audio_ =
    Effect { effectType = ScaleVolume { scaleBy = scaleBy, startTime = Quantity.zero }, audio = audio_ }


scaleVolumeAt : Float -> Duration -> Audio -> Audio
scaleVolumeAt scaleBy startTime audio_ =
    Effect { effectType = ScaleVolume { scaleBy = scaleBy, startTime = startTime }, audio = audio_ }


scalePlaybackRateAt : Float -> Duration -> Audio -> Audio
scalePlaybackRateAt scaleBy startTime audio_ =
    Effect { effectType = ScalePlaybackRate { scaleBy = scaleBy, startTime = startTime }, audio = audio_ }


group : List Audio -> Audio
group audios =
    Group audios


silence : Audio
silence =
    group []


type Error
    = AudioLoadingRelatedErrors


loadAudio : String -> Task Error (AudioSource -> msg)
loadAudio url =
    Debug.todo ""


sineWave : Float -> AudioSource
sineWave frequency =
    SineWave { frequency = frequency }
