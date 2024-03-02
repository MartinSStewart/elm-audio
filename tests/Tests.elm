module Tests exposing (suite)

import Audio exposing (BufferId(..))
import Dict
import Duration
import Expect
import Json.Encode
import Test exposing (Test, test)
import Time


{-| In order to run the tests you'll need to temporarily change Audio.elm to expose all
-}
suite : Test
suite =
    test "Update loop correctly" <|
        \_ ->
            let
                startTime =
                    Time.millisToPosix 100000

                oldAudio =
                    Audio.audio (Audio.File { bufferId = BufferId 1 }) startTime

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

                jsonText =
                    List.map (Json.Encode.encode 0) json
            in
            Expect.equal
                ( Dict.fromList
                    [ ( 0
                      , { loop = Just { loopEnd = Duration.seconds 10, loopStart = Duration.seconds 0 }
                        , offset = Duration.seconds 0
                        , playbackRate = 1
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
