module Tests exposing (suite)

import Audio exposing (Audio, BufferId(..))
import Dict
import Duration
import Expect
import Json.Decode
import Json.Encode
import Test exposing (Test, describe, test)
import Time


{-| In order to run the tests you'll need to temporarily change Audio.elm to expose all
-}
suite : Test
suite =
    describe "Audio"
        [ updateLoopTest
        , panTests
        ]


startTime : Time.Posix
startTime =
    Time.millisToPosix 100000


sound : Audio
sound =
    Audio.audio (Audio.File { bufferId = BufferId 1 }) startTime


{-| The messages for JS after the audio changes from `oldAudio` to `newAudio`.
-}
diffJson : Audio -> Audio -> List String
diffJson oldAudio newAudio =
    let
        ( startDiff, nodeGroupCounter, _ ) =
            Audio.diffAudioState 0 Dict.empty oldAudio

        ( _, _, json ) =
            Audio.diffAudioState nodeGroupCounter startDiff newAudio
    in
    List.map (Json.Encode.encode 0) json


{-| The pan each sound starts with, when `audio` starts playing.
-}
startPans : Audio -> List (Result Json.Decode.Error Float)
startPans audio =
    let
        ( _, _, json ) =
            Audio.diffAudioState 0 Dict.empty audio
    in
    List.map (Json.Decode.decodeValue (Json.Decode.field "pan" Json.Decode.float)) json


panTests : Test
panTests =
    describe "pan"
        [ test "A sound starts centered" <|
            \_ ->
                startPans sound |> Expect.equal [ Ok 0 ]
        , test "A panned sound starts with its pan" <|
            \_ ->
                startPans (Audio.pan -0.25 sound) |> Expect.equal [ Ok -0.25 ]
        , test "Nested pans add up" <|
            \_ ->
                startPans (Audio.pan 0.25 (Audio.group [ Audio.pan 0.5 sound ])) |> Expect.equal [ Ok 0.75 ]
        , test "The sum is clamped, whatever the nesting order" <|
            \_ ->
                [ startPans (Audio.pan 1 (Audio.pan 1 (Audio.pan -1 sound)))
                , startPans (Audio.pan -1 (Audio.pan 1 (Audio.pan 1 sound)))
                , startPans (Audio.pan 0.75 (Audio.pan 0.75 sound))
                ]
                    |> Expect.equal [ [ Ok 1 ], [ Ok 1 ], [ Ok 1 ] ]
        , test "Changing the pan of a playing sound sends setPan" <|
            \_ ->
                diffJson (Audio.pan 0.5 sound) (Audio.pan -0.5 sound)
                    |> Expect.equal [ "{\"nodeGroupId\":0,\"action\":\"setPan\",\"pan\":-0.5}" ]
        , test "A pan change that clamps to the same value sends nothing" <|
            \_ ->
                diffJson (Audio.pan 2 sound) (Audio.pan 1.5 sound) |> Expect.equal []
        ]


updateLoopTest : Test
updateLoopTest =
    test "Update loop correctly" <|
        \_ ->
            let
                oldAudio : Audio
                oldAudio =
                    sound

                newAudio : Audio
                newAudio =
                    Audio.audioWithConfig
                        { loop = Just { loopStart = Duration.seconds 0, loopEnd = Duration.seconds 10 }
                        , playbackRate = 1
                        , startAt = Duration.seconds 0
                        }
                        (Audio.File { bufferId = BufferId 1 })
                        startTime

                ( startDiff, nodeGroupCounter, _ ) =
                    Audio.diffAudioState 0 Dict.empty oldAudio

                ( newDiff, _, json ) =
                    Audio.diffAudioState nodeGroupCounter startDiff newAudio

                jsonText : List String
                jsonText =
                    List.map (Json.Encode.encode 0) json
            in
            Expect.equal
                ( Dict.fromList
                    [ ( 0
                      , { loop = Just { loopEnd = Duration.seconds 10, loopStart = Duration.seconds 0 }
                        , offset = Duration.seconds 0
                        , playbackRate = 1
                        , pan = 0
                        , source = Audio.File { bufferId = BufferId 1 }
                        , startAt = Duration.seconds 0
                        , startTime = startTime
                        , volume = 1
                        , volumeTimelines = []
                        }
                      )
                    ]
                , [ "{\"nodeGroupId\":0,\"action\":\"setLoopConfig\",\"loop\":{\"loopStart\":0,\"loopEnd\":10000}}" ]
                )
                ( newDiff, jsonText )
