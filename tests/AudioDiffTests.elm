module AudioDiffTests exposing (suite)

{-| Regression tests for the vendored `Audio` module's diffing (`diffAudioState`).

The diff turns the currently playing audio into the audio the `audio` function
now wants, emitting the minimal set of port messages to get there. The whole
point of the optimization is that when little changes between two audio values,
the diff does little work and emits few messages — most importantly, an
unchanged audio value emits nothing at all. These tests pin that behaviour down
so a future rewrite can't silently start re-sending every sound each frame.

-}

import Audio exposing (Audio, FlattenedAudio)
import Dict exposing (Dict)
import Expect
import Json.Decode as JD
import Json.Encode as JE
import Test exposing (Test, describe, test)
import Time


{-| A plain sound from the given buffer, starting at the given time (ms).
-}
note : Int -> Int -> Audio
note bufferId startMillis =
    Audio.audio (Audio.sourceWithBufferId bufferId) (Time.millisToPosix startMillis)


{-| Build the "currently playing" state the way the diff itself does: one entry
per flattened sound, keyed by a distinct node-group id. The exact ids don't
matter because the diff matches sounds by identity, not by id.
-}
stateFrom : Audio -> Dict Int FlattenedAudio
stateFrom audio =
    Audio.flattenAudio audio
        |> List.indexedMap Tuple.pair
        |> Dict.fromList


{-| The port messages emitted when moving from `before` to `after`.
-}
diff : Audio -> Audio -> List JE.Value
diff before after =
    let
        state =
            stateFrom before

        ( _, _, json ) =
            Audio.diffAudioState (Dict.size state) state after
    in
    json


{-| The `action` tag of each emitted message (e.g. "startSound", "setVolume").
-}
actions : List JE.Value -> List String
actions json =
    List.filterMap
        (\value -> JD.decodeValue (JD.field "action" JD.string) value |> Result.toMaybe)
        json


{-| Count how many times each action appears, order-independently.
-}
actionCounts : List JE.Value -> Dict String Int
actionCounts json =
    List.foldl
        (\action -> Dict.update action (\count -> Just (1 + Maybe.withDefault 0 count)))
        Dict.empty
        (actions json)


manyNotes : Int -> List Audio
manyNotes count =
    List.range 0 (count - 1)
        |> List.map (\i -> note i (1000 + i * 100))


suite : Test
suite =
    describe "Audio.diffAudioState"
        [ test "identical audio emits no messages" <|
            \_ ->
                let
                    audio =
                        Audio.group [ note 0 1000, note 1 2000, note 0 3000 ]
                in
                Expect.equal [] (actions (diff audio audio))
        , test "re-diffing the state the diff just produced emits nothing" <|
            \_ ->
                let
                    audio =
                        Audio.group (manyNotes 20)

                    -- Start from nothing, then diff the identical audio again.
                    ( state, counter, _ ) =
                        Audio.diffAudioState 0 Dict.empty audio

                    ( _, _, json ) =
                        Audio.diffAudioState counter state audio
                in
                Expect.equal [] (actions json)
        , test "adding one sound emits exactly one startSound" <|
            \_ ->
                let
                    before =
                        Audio.group (manyNotes 30)

                    after =
                        Audio.group (manyNotes 30 ++ [ note 999 99999 ])
                in
                Expect.equal [ "startSound" ] (actions (diff before after))
        , test "removing one sound emits exactly one stopSound" <|
            \_ ->
                let
                    after =
                        Audio.group (manyNotes 30)

                    before =
                        Audio.group (manyNotes 30 ++ [ note 999 99999 ])
                in
                Expect.equal [ "stopSound" ] (actions (diff before after))
        , test "changing one sound's volume emits exactly one setVolume" <|
            \_ ->
                let
                    before =
                        Audio.group (manyNotes 40)

                    after =
                        manyNotes 40
                            |> List.indexedMap
                                (\i n ->
                                    if i == 20 then
                                        Audio.scaleVolume 0.5 n

                                    else
                                        n
                                )
                            |> Audio.group
                in
                Expect.equal [ "setVolume" ] (actions (diff before after))
        , test "changing one sound's playback rate emits exactly one setPlaybackRate" <|
            \_ ->
                let
                    config =
                        Audio.audioDefaultConfig

                    before =
                        Audio.group (manyNotes 10)

                    after =
                        manyNotes 10
                            |> List.indexedMap
                                (\i n ->
                                    if i == 3 then
                                        Audio.audioWithConfig
                                            { config | playbackRate = 2 }
                                            (Audio.sourceWithBufferId 3)
                                            (Time.millisToPosix (1000 + 3 * 100))

                                    else
                                        n
                                )
                            |> Audio.group
                in
                Expect.equal [ "setPlaybackRate" ] (actions (diff before after))
        , test "a wholly different set stops every old sound and starts every new one" <|
            \_ ->
                let
                    before =
                        Audio.group [ note 0 1000, note 1 2000 ]

                    after =
                        Audio.group [ note 5 5000, note 6 6000 ]
                in
                Expect.equal
                    (Dict.fromList [ ( "startSound", 2 ), ( "stopSound", 2 ) ])
                    (actionCounts (diff before after))
        , test "moving one sound in time restarts just that sound" <|
            \_ ->
                let
                    before =
                        Audio.group [ note 0 1000, note 1 2000, note 2 3000 ]

                    -- note 2 now starts at a different time, so it counts as a
                    -- different sound: stop the old one, start the new one.
                    after =
                        Audio.group [ note 0 1000, note 1 2000, note 2 3500 ]
                in
                Expect.equal
                    (Dict.fromList [ ( "startSound", 1 ), ( "stopSound", 1 ) ])
                    (actionCounts (diff before after))
        , test "silence stops all currently playing sounds" <|
            \_ ->
                let
                    before =
                        Audio.group (manyNotes 5)
                in
                Expect.equal
                    (Dict.fromList [ ( "stopSound", 5 ) ])
                    (actionCounts (diff before Audio.silence))
        , test "duplicate identical sounds are matched one-for-one (no spurious messages)" <|
            \_ ->
                let
                    -- Two sounds that share the very same identity and settings.
                    audio =
                        Audio.group [ note 7 4000, note 7 4000 ]
                in
                Expect.equal [] (actions (diff audio audio))
        ]
