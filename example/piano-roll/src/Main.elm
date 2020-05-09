port module Main exposing (..)

import Audio exposing (Audio, AudioCmd)
import Browser.Events
import Duration exposing (Duration)
import Html exposing (Html)
import Html.Events
import Json.Decode
import Json.Encode
import Quantity
import Task
import Time


type alias Model =
    { soundState : SoundState }


type SoundState
    = NotPlaying
    | Playing Time.Posix
    | Paused { startTime : Time.Posix, pauseTime : Time.Posix }


type Msg
    = PressedPlay
    | PressedPlayAndGotTime Time.Posix
    | PressedStop
    | PressedStopAndGotTime Time.Posix
    | AnimationFrame Time.Posix


init : flags -> ( Model, Cmd Msg, AudioCmd Msg )
init _ =
    ( { soundState = NotPlaying }, Cmd.none, Audio.cmdNone )


update : Msg -> Model -> ( Model, Cmd Msg, AudioCmd Msg )
update msg model =
    case msg of
        PressedPlay ->
            ( model
            , Task.perform PressedPlayAndGotTime Time.now
            , Audio.cmdNone
            )

        PressedPlayAndGotTime time ->
            ( { model
                | soundState =
                    case model.soundState of
                        NotPlaying ->
                            Playing time

                        Playing _ ->
                            model.soundState

                        Paused { startTime, pauseTime } ->
                            Duration.from pauseTime time |> Duration.addTo startTime |> Playing
              }
            , Cmd.none
            , Audio.cmdNone
            )

        PressedStop ->
            ( model
            , Task.perform PressedStopAndGotTime Time.now
            , Audio.cmdNone
            )

        PressedStopAndGotTime stopTime ->
            case model.soundState of
                Playing startTime ->
                    ( { model | soundState = NotPlaying }
                    , Cmd.none
                    , Audio.cmdNone
                    )

                _ ->
                    ( model, Cmd.none, Audio.cmdNone )

        _ ->
            ( model, Cmd.none, Audio.cmdNone )


view : Model -> Html Msg
view model =
    case model.soundState of
        Playing _ ->
            Html.div
                []
                [ Html.button [ Html.Events.onClick PressedStop ] [ Html.text "Stop music" ] ]

        _ ->
            Html.div
                []
                [ Html.button [ Html.Events.onClick PressedPlay ] [ Html.text "Play music!" ] ]


frequency : Int -> Audio.Frequency
frequency value =
    440 * (1.059463 ^ toFloat value) |> Audio.cyclesPerSecond


note : Time.Posix -> Int -> Float -> Audio
note musicStart noteOffset timeOffset =
    let
        noteLength =
            Duration.milliseconds 150

        startTime =
            Duration.addTo musicStart (Quantity.multiplyBy timeOffset beatLength)
    in
    Audio.square (frequency noteOffset) startTime
        |> Audio.scaleVolumeAt
            [ ( startTime, 0.5 )
            , ( Duration.addTo startTime (Quantity.multiplyBy 0.95 noteLength), 0.3 )
            , ( Duration.addTo startTime noteLength, 0 )
            ]


beatLength : Duration
beatLength =
    Duration.milliseconds 150


percussion : Time.Posix -> Float -> Audio
percussion =
    percussionHelper (Duration.milliseconds 150)


percussionShort : Time.Posix -> Float -> Audio
percussionShort =
    percussionHelper (Duration.milliseconds 75)


percussionHelper : Duration -> Time.Posix -> Float -> Audio
percussionHelper duration musicStart timeOffset =
    let
        startTime =
            Duration.addTo musicStart (Quantity.multiplyBy timeOffset beatLength)
    in
    Audio.whiteNoise startTime
        |> Audio.scaleVolumeAt
            [ ( startTime, 0.5 )
            , ( Duration.addTo startTime duration, 0 )
            ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onAnimationFrame AnimationFrame


audio : Model -> Audio
audio model =
    case model.soundState of
        NotPlaying ->
            Audio.silence

        Playing startTime ->
            Audio.group
                [ note startTime 7 0
                , note startTime -3 0
                , percussion startTime 0
                , note startTime 7 1
                , note startTime -3 1
                , percussionShort startTime 1
                , note startTime 7 3
                , note startTime -3 3
                , percussion startTime 3
                , note startTime 3 5
                , note startTime -3 5
                , percussionShort startTime 5
                , note startTime 7 6
                , note startTime -3 6
                , percussion startTime 6
                , note startTime 10 8
                , note startTime 2 8
                , note startTime -2 8
                , percussionShort startTime 8
                , note startTime -2 12
                , percussionShort startTime 12
                , percussionShort startTime 13
                , percussionShort startTime 14
                ]

        Paused { startTime, pauseTime } ->
            Audio.silence


notes =
    []


port audioPortToJS : Json.Encode.Value -> Cmd msg


port audioPortFromJS : (Json.Decode.Value -> msg) -> Sub msg


main : Platform.Program () (Audio.Model Msg Model) (Audio.Msg Msg)
main =
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , audio = audio
        , audioPort = { toJS = audioPortToJS, fromJS = audioPortFromJS }
        }
