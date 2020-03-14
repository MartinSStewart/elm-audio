port module Main exposing (..)

import Audio exposing (Audio, AudioCmd)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode
import Json.Encode
import List.Nonempty exposing (Nonempty(..))
import Task
import Time


type alias LoadedModel_ =
    { sound : Audio.Source
    , soundState : SoundState
    }


type SoundState
    = NotPlaying
    | Playing Time.Posix
    | FadingOut Time.Posix Time.Posix


type Model
    = LoadingModel
    | LoadedModel LoadedModel_
    | LoadFailedModel


type Msg
    = SoundLoaded (Result Audio.LoadError Audio.Source)
    | PressedPlay
    | PressedPlayAndGotTime Time.Posix
    | PressedStop
    | PressedStopAndGotTime Time.Posix


init : flags -> ( Model, Cmd Msg, AudioCmd Msg )
init _ =
    ( LoadingModel
    , Cmd.none
    , Audio.loadAudio
        SoundLoaded
        "https://cors-anywhere.herokuapp.com/https://freepd.com/music/Wakka%20Wakka.mp3"
    )


update : Msg -> Model -> ( Model, Cmd Msg, AudioCmd Msg )
update msg model =
    case ( msg, model ) of
        ( SoundLoaded result, LoadingModel ) ->
            case result of
                Ok sound ->
                    ( LoadedModel { sound = sound, soundState = NotPlaying }
                    , Cmd.none
                    , Audio.cmdNone
                    )

                Err _ ->
                    ( LoadFailedModel
                    , Cmd.none
                    , Audio.cmdNone
                    )

        ( PressedPlay, LoadedModel loadedModel ) ->
            ( LoadedModel loadedModel
            , Task.perform PressedPlayAndGotTime Time.now
            , Audio.cmdNone
            )

        ( PressedPlayAndGotTime time, LoadedModel loadedModel ) ->
            ( LoadedModel { loadedModel | soundState = Playing time }
            , Cmd.none
            , Audio.cmdNone
            )

        ( PressedStop, LoadedModel loadedModel ) ->
            ( LoadedModel loadedModel
            , Task.perform PressedStopAndGotTime Time.now
            , Audio.cmdNone
            )

        ( PressedStopAndGotTime stopTime, LoadedModel loadedModel ) ->
            case loadedModel.soundState of
                Playing startTime ->
                    ( LoadedModel { loadedModel | soundState = FadingOut startTime stopTime }
                    , Cmd.none
                    , Audio.cmdNone
                    )

                _ ->
                    ( model, Cmd.none, Audio.cmdNone )

        _ ->
            ( model, Cmd.none, Audio.cmdNone )


view : Model -> Html Msg
view model =
    case model of
        LoadingModel ->
            Html.text "Loading..."

        LoadedModel loadingModel ->
            case loadingModel.soundState of
                Playing _ ->
                    Html.div
                        []
                        [ Html.button [ Html.Events.onClick PressedStop ] [ Html.text "Stop music" ] ]

                _ ->
                    Html.div
                        []
                        [ Html.button [ Html.Events.onClick PressedPlay ] [ Html.text "Play music!" ] ]

        LoadFailedModel ->
            Html.text "Failed to load sound."


audio : Model -> Audio
audio model =
    case model of
        LoadedModel loadedModel ->
            case loadedModel.soundState of
                NotPlaying ->
                    Audio.silence

                Playing time ->
                    Audio.audio loadedModel.sound time

                FadingOut startTime stopTime ->
                    Audio.audio loadedModel.sound startTime
                        |> Audio.scaleVolumeAt
                            (Nonempty
                                ( stopTime, 1 )
                                [ ( addMillis 2000 stopTime, 0 ) ]
                            )

        _ ->
            Audio.silence


addMillis : Int -> Time.Posix -> Time.Posix
addMillis millis =
    Time.posixToMillis >> (+) millis >> Time.millisToPosix


port audioPortToJS : Json.Encode.Value -> Cmd msg


port audioPortFromJS : (Json.Decode.Value -> msg) -> Sub msg


main : Audio.Program () Model Msg
main =
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = always Sub.none
        , audio = audio
        , audioPort = { toJS = audioPortToJS, fromJS = audioPortFromJS }
        }
