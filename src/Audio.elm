module Audio exposing
    ( elementWithAudio, documentWithAudio, applicationWithAudio, Model, Msg, AudioData
    , AudioCmd, loadAudio, LoadError(..), Source, cmdMap, cmdBatch, cmdNone
    , Audio, audio, group, silence, length, audioWithConfig, audioDefaultConfig, PlayAudioConfig, LoopConfig
    , scaleVolume, scaleVolumeAt, offsetBy
    , lamderaFrontendWithAudio, migrateModel, migrateMsg
    , FlattenedAudio, diffAudioState, flattenAudio, sourceWithBufferId
    )

{-|


# Applications

Create an Elm app that supports playing audio.

@docs elementWithAudio, documentWithAudio, applicationWithAudio, Model, Msg, AudioData


# Load audio

Load audio so you can later play it.

@docs AudioCmd, loadAudio, LoadError, Source, cmdMap, cmdBatch, cmdNone


# Play audio

Define what audio should be playing.

@docs Audio, audio, group, silence, length, audioWithConfig, audioDefaultConfig, PlayAudioConfig, LoopConfig


# Audio effects

Effects you can apply to `Audio`.

@docs scaleVolume, scaleVolumeAt, offsetBy


# Lamdera stuff

WIP support for Lamdera. Ignore this for now.

@docs lamderaFrontendWithAudio, migrateModel, migrateMsg

-}

import Browser
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Duration exposing (Duration)
import Html exposing (Html)
import Json.Decode as JD
import Json.Encode as JE
import List.Nonempty as Nonempty exposing (Nonempty)
import Quantity
import Time
import Url exposing (Url)


{-| The top level model for our program.
This contains the model for your app as well as extra data needed to keep track of what audio is playing.
-}
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
    , sourceData : Dict Int SourceData

    -- The audio value that produced the current audioState. Keeping it lets us
    -- skip diffing entirely when the audio function returns the same thing it
    -- did last time (the common case when only unrelated model fields change,
    -- e.g. an animation-frame clock driving the view).
    , lastAudio : Audio
    }


type alias SourceData =
    { duration : Duration }


{-| Information about audio files you have loaded.
This is passed as a parameter to your update, view, subscriptions, and audio functions.
-}
type AudioData
    = AudioData
        { sourceData : Dict Int SourceData
        }


audioData : Model userMsg userModel -> AudioData
audioData (Model model) =
    { sourceData = model.sourceData
    }
        |> AudioData


{-| Get how long an audio source plays for.
-}
length : AudioData -> Source -> Duration
length (AudioData audioData_) source =
    Dict.get (audioSourceBufferId source |> rawBufferId) audioData_.sourceData
        |> Maybe.map .duration
        -- We should always be able to find the bufferId so this should never default to 0.
        |> Maybe.withDefault Quantity.zero


{-| The top level msg for our program.
This contains the msg type your app uses in addition to msgs that are needed to handle when audio gets loaded.
-}
type Msg userMsg
    = FromJSMsg FromJSMsg
    | UserMsg userMsg


type FromJSMsg
    = AudioLoadSuccess { requestId : Int, bufferId : BufferId, duration : Duration }
    | AudioLoadFailed { requestId : Int, error : LoadError }
    | InitAudioContext { samplesPerSecond : Int }
    | JsonParseError { error : String }


type alias AudioLoadRequest_ userMsg =
    { userMsg : Nonempty ( Result LoadError Source, userMsg ), audioUrl : String }


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


{-| Map a command from one type to another. Conceptually the same as Cmd.map.
-}
cmdMap : (a -> b) -> AudioCmd a -> AudioCmd b
cmdMap map cmd =
    case cmd of
        AudioLoadRequest audioLoadRequest_ ->
            mapAudioLoadRequest map audioLoadRequest_
                |> AudioLoadRequest

        AudioCmdGroup audioCmds ->
            audioCmds |> List.map (cmdMap map) |> AudioCmdGroup


mapAudioLoadRequest : (a -> b) -> AudioLoadRequest_ a -> AudioLoadRequest_ b
mapAudioLoadRequest mapFunc audioLoadRequest =
    { userMsg = Nonempty.map (Tuple.mapSecond mapFunc) audioLoadRequest.userMsg
    , audioUrl = audioLoadRequest.audioUrl
    }


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
    , view : AudioData -> model -> Html msg
    , update : AudioData -> msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : AudioData -> model -> Sub msg
    , audio : AudioData -> model -> Audio
    , audioPort : Ports msg
    }
    -> Platform.Program flags (Model msg model) (Msg msg)
elementWithAudio =
    withAudioOffset
        >> (\app ->
                { init = app.init >> initHelper app.audioPort.toJS app.audio
                , view = \model -> getUserModel model |> app.view (audioData model) |> Html.map UserMsg
                , update = update app
                , subscriptions = subscriptions app
                }
                    |> Browser.element
           )


{-| Browser.document but with the ability to play sounds.
-}
documentWithAudio :
    { init : flags -> ( model, Cmd msg, AudioCmd msg )
    , view : AudioData -> model -> Browser.Document msg
    , update : AudioData -> msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : AudioData -> model -> Sub msg
    , audio : AudioData -> model -> Audio
    , audioPort : Ports msg
    }
    -> Platform.Program flags (Model msg model) (Msg msg)
documentWithAudio =
    withAudioOffset
        >> (\app ->
                { init = app.init >> initHelper app.audioPort.toJS app.audio
                , view =
                    \model ->
                        let
                            { title, body } =
                                app.view (audioData model) (getUserModel model)
                        in
                        { title = title
                        , body = body |> List.map (Html.map UserMsg)
                        }
                , update = update app
                , subscriptions = subscriptions app
                }
                    |> Browser.document
           )


{-| Browser.application but with the ability to play sounds.
-}
applicationWithAudio :
    { init : flags -> Url -> Key -> ( model, Cmd msg, AudioCmd msg )
    , view : AudioData -> model -> Browser.Document msg
    , update : AudioData -> msg -> model -> ( model, Cmd msg, AudioCmd msg )
    , subscriptions : AudioData -> model -> Sub msg
    , onUrlRequest : Browser.UrlRequest -> msg
    , onUrlChange : Url -> msg
    , audio : AudioData -> model -> Audio
    , audioPort : Ports msg
    }
    -> Platform.Program flags (Model msg model) (Msg msg)
applicationWithAudio =
    withAudioOffset
        >> (\app ->
                { init = \flags url key -> app.init flags url key |> initHelper app.audioPort.toJS app.audio
                , view =
                    \model ->
                        let
                            { title, body } =
                                app.view (audioData model) (getUserModel model)
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
           )


{-| Lamdera.frontend but with the ability to play sounds (highly experimental, just ignore this for now).
-}
lamderaFrontendWithAudio :
    { init : Url.Url -> Browser.Navigation.Key -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , view : AudioData -> model -> Browser.Document frontendMsg
    , update : AudioData -> frontendMsg -> model -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , updateFromBackend : AudioData -> toFrontend -> model -> ( model, Cmd frontendMsg, AudioCmd frontendMsg )
    , subscriptions : AudioData -> model -> Sub frontendMsg
    , onUrlRequest : Browser.UrlRequest -> frontendMsg
    , onUrlChange : Url -> frontendMsg
    , audio : AudioData -> model -> Audio
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
lamderaFrontendWithAudio =
    withAudioOffset
        >> (\app ->
                { init = \url key -> initHelper app.audioPort.toJS app.audio (app.init url key)
                , view =
                    \model ->
                        let
                            { title, body } =
                                app.view (audioData model) (getUserModel model)
                        in
                        { title = title
                        , body = body |> List.map (Html.map UserMsg)
                        }
                , update = update app
                , updateFromBackend =
                    \toFrontend model ->
                        updateHelper app.audioPort.toJS app.audio (flip app.updateFromBackend toFrontend) model
                , subscriptions = subscriptions app
                , onUrlRequest = app.onUrlRequest >> UserMsg
                , onUrlChange = app.onUrlChange >> UserMsg
                }
           )


withAudioOffset app =
    { app | audio = \audioData_ model -> app.audio audioData_ model |> offsetBy (Duration.milliseconds 50) }


{-| Use this function when migrating your model in Lamdera.
-}
migrateModel :
    (msgOld -> msgNew)
    -> (modelOld -> ( modelNew, Cmd msgNew ))
    -> Model msgOld modelOld
    -> ( Model msgNew modelNew, Cmd msgNew )
migrateModel msgMigrate modelMigrate (Model model) =
    let
        ( newModel, cmd ) =
            modelMigrate model.userModel
    in
    ( Model
        { userModel = newModel
        , nodeGroupIdCounter = model.nodeGroupIdCounter
        , samplesPerSecond = model.samplesPerSecond
        , audioState = model.audioState
        , pendingRequests = Dict.map (\_ value -> mapAudioLoadRequest msgMigrate value) model.pendingRequests
        , requestCount = model.requestCount
        , sourceData = model.sourceData
        , lastAudio = model.lastAudio
        }
    , cmd
    )


{-| Use this function when migrating messages in Lamdera.
-}
migrateMsg : (msgOld -> ( msgNew, Cmd msgNew )) -> Msg msgOld -> ( Msg msgNew, Cmd msgNew )
migrateMsg msgMigrate msg =
    case msg of
        FromJSMsg fromJSMsg ->
            ( FromJSMsg fromJSMsg, Cmd.none )

        UserMsg userMsg ->
            msgMigrate userMsg |> Tuple.mapFirst UserMsg


updateHelper :
    (JD.Value -> Cmd (Msg userMsg))
    -> (AudioData -> userModel -> Audio)
    -> (AudioData -> userModel -> ( userModel, Cmd userMsg, AudioCmd userMsg ))
    -> Model userMsg userModel
    -> ( Model userMsg userModel, Cmd (Msg userMsg) )
updateHelper audioPort audioFunc userUpdate (Model model) =
    let
        audioData_ =
            audioData (Model model)

        ( newUserModel, userCmd, audioCmds ) =
            userUpdate audioData_ model.userModel

        newAudio =
            audioFunc audioData_ newUserModel

        ( audioState, newNodeGroupIdCounter, json ) =
            if newAudio == model.lastAudio then
                -- Nothing about the audio changed, so there is nothing to diff
                -- and no messages to send. This is what keeps frequent updates
                -- (like a 60fps clock) from doing O(sounds) work every frame.
                ( model.audioState, model.nodeGroupIdCounter, [] )

            else
                diffAudioState model.nodeGroupIdCounter model.audioState newAudio

        newModel : Model userMsg userModel
        newModel =
            Model
                { model
                    | audioState = audioState
                    , nodeGroupIdCounter = newNodeGroupIdCounter
                    , userModel = newUserModel
                    , lastAudio = newAudio
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
    -> (AudioData -> model -> Audio)
    -> ( model, Cmd userMsg, AudioCmd userMsg )
    -> ( Model userMsg model, Cmd (Msg userMsg) )
initHelper audioPort audioFunc ( model, cmds, audioCmds ) =
    let
        initialAudio =
            audioFunc (AudioData { sourceData = Dict.empty }) model

        ( audioState, newNodeGroupIdCounter, json ) =
            diffAudioState 0 Dict.empty initialAudio

        initialModel =
            Model
                { audioState = audioState
                , nodeGroupIdCounter = newNodeGroupIdCounter
                , userModel = model
                , requestCount = 0
                , pendingRequests = Dict.empty
                , samplesPerSecond = Nothing
                , sourceData = Dict.empty
                , lastAudio = initialAudio
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


{-| Borrowed from List.Extra so we don't need to depend on the entire package.
-}
find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest


flip : (c -> b -> a) -> b -> c -> a
flip func a b =
    func b a


update :
    { a
        | audioPort : Ports userMsg
        , audio : AudioData -> userModel -> Audio
        , update : AudioData -> userMsg -> userModel -> ( userModel, Cmd userMsg, AudioCmd userMsg )
    }
    -> Msg userMsg
    -> Model userMsg userModel
    -> ( Model userMsg userModel, Cmd (Msg userMsg) )
update app msg (Model model) =
    case msg of
        UserMsg userMsg ->
            updateHelper app.audioPort.toJS app.audio (flip app.update userMsg) (Model model)

        FromJSMsg response ->
            case response of
                AudioLoadSuccess { requestId, bufferId, duration } ->
                    case Dict.get requestId model.pendingRequests of
                        Just pendingRequest ->
                            let
                                source =
                                    { bufferId = bufferId } |> File |> Ok

                                maybeUserMsg =
                                    Nonempty.toList pendingRequest.userMsg |> find (Tuple.first >> (==) source)

                                sourceData =
                                    Dict.insert (rawBufferId bufferId) { duration = duration } model.sourceData
                            in
                            case maybeUserMsg of
                                Just ( _, userMsg ) ->
                                    { model
                                        | pendingRequests = Dict.remove requestId model.pendingRequests
                                        , sourceData = sourceData
                                    }
                                        |> Model
                                        |> updateHelper
                                            app.audioPort.toJS
                                            app.audio
                                            (flip app.update userMsg)

                                Nothing ->
                                    { model
                                        | pendingRequests = Dict.remove requestId model.pendingRequests
                                        , sourceData = sourceData
                                    }
                                        |> Model
                                        |> updateHelper
                                            app.audioPort.toJS
                                            app.audio
                                            (Nonempty.head pendingRequest.userMsg
                                                |> Tuple.second
                                                |> flip app.update
                                            )

                        Nothing ->
                            ( Model model, Cmd.none )

                AudioLoadFailed { requestId, error } ->
                    case Dict.get requestId model.pendingRequests of
                        Just pendingRequest ->
                            let
                                a =
                                    Err error

                                b =
                                    Nonempty.toList pendingRequest.userMsg |> find (Tuple.first >> (==) a)
                            in
                            case b of
                                Just ( _, userMsg ) ->
                                    { model | pendingRequests = Dict.remove requestId model.pendingRequests }
                                        |> Model
                                        |> updateHelper
                                            app.audioPort.toJS
                                            app.audio
                                            (flip app.update userMsg)

                                Nothing ->
                                    { model | pendingRequests = Dict.remove requestId model.pendingRequests }
                                        |> Model
                                        |> updateHelper
                                            app.audioPort.toJS
                                            app.audio
                                            (Nonempty.head pendingRequest.userMsg |> Tuple.second |> flip app.update)

                        Nothing ->
                            ( Model model, Cmd.none )

                InitAudioContext { samplesPerSecond } ->
                    ( Model { model | samplesPerSecond = Just samplesPerSecond }, Cmd.none )

                JsonParseError { error } ->
                    ( Model model, Cmd.none )


subscriptions :
    { a | subscriptions : AudioData -> userModel -> Sub userMsg, audioPort : Ports userMsg }
    -> Model userMsg userModel
    -> Sub (Msg userMsg)
subscriptions app (Model model) =
    Sub.batch [ app.subscriptions (audioData (Model model)) model.userModel |> Sub.map UserMsg, app.audioPort.fromJS fromJSPortSub ]


decodeLoadError : JD.Decoder LoadError
decodeLoadError =
    JD.string
        |> JD.andThen
            (\value ->
                case value of
                    "NetworkError" ->
                        JD.succeed NetworkError

                    "MediaDecodeAudioDataUnknownContentType" ->
                        JD.succeed FailedToDecode

                    "DOMException: The buffer passed to decodeAudioData contains an unknown content type." ->
                        JD.succeed FailedToDecode

                    _ ->
                        JD.succeed UnknownError
            )


decodeFromJSMsg : JD.Decoder FromJSMsg
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


rawBufferId : BufferId -> Int
rawBufferId (BufferId bufferId) =
    bufferId


encodeBufferId : BufferId -> JE.Value
encodeBufferId (BufferId bufferId) =
    JE.int bufferId


decodeBufferId : JD.Decoder BufferId
decodeBufferId =
    JD.int |> JD.map BufferId


{-| The identity of a playing sound: it comes from the same buffer, starts at
the same wall-clock time (offset included), and starts from the same point
within the buffer. Two sounds that share a key are "the same sound" whose
remaining settings (volume, loop, playback rate, volume timeline) might still
differ and need updating.

Computing this once per sound and grouping by it is what lets the diff avoid
re-scanning the whole new-audio list for every currently playing sound.

-}
type alias AudioKey =
    ( Int, Int, Float )


audioKey : FlattenedAudio -> AudioKey
audioKey a =
    ( audioSourceBufferId a.source |> rawBufferId
    , audioStartTime a |> Time.posixToMillis
    , a.startAt |> Duration.inMilliseconds
    )


{-| Figure out the minimal set of changes needed to turn the currently playing
audio (`audioState`) into `newAudio`, returning the updated state, the next
free node-group id, and the port messages describing the changes.

The new audio is bucketed by [`audioKey`](#audioKey) so each existing sound is
reconciled with a dictionary lookup rather than a linear scan of every new
sound. That makes the whole diff roughly `O((n + m) * log n)` instead of
`O(n * m)`, and — crucially — when little or nothing has changed almost every
existing sound finds an exact match and contributes no work and no messages.

-}
diffAudioState : Int -> Dict NodeGroupId FlattenedAudio -> Audio -> ( Dict NodeGroupId FlattenedAudio, Int, List JE.Value )
diffAudioState nodeGroupIdCounter audioState newAudio =
    let
        -- Group the new audio by identity. Buckets are never stored empty, and
        -- keep their sounds in the original flattened order so that ties are
        -- broken the same way regardless of how many sounds share a key.
        buckets : Dict AudioKey (List FlattenedAudio)
        buckets =
            List.foldr
                (\a acc ->
                    Dict.update (audioKey a)
                        (\existing -> Just (a :: Maybe.withDefault [] existing))
                        acc
                )
                Dict.empty
                (flattenAudio newAudio)

        -- Reconcile every currently playing sound: leave exact matches alone,
        -- update sounds whose settings changed, and stop sounds that are gone.
        ( remainingBuckets, keptState, updateJson ) =
            Dict.foldl reconcileExistingAudio ( buckets, Dict.empty, [] ) audioState

        -- Any new sounds still left in the buckets had no counterpart, so they
        -- get started with fresh node-group ids.
        ( newNodeGroupIdCounter, newAudioState, json ) =
            Dict.foldl
                (\_ bucket acc -> List.foldl startNewAudio acc bucket)
                ( nodeGroupIdCounter, keptState, updateJson )
                remainingBuckets
    in
    ( newAudioState, newNodeGroupIdCounter, json )


reconcileExistingAudio :
    NodeGroupId
    -> FlattenedAudio
    -> ( Dict AudioKey (List FlattenedAudio), Dict NodeGroupId FlattenedAudio, List JE.Value )
    -> ( Dict AudioKey (List FlattenedAudio), Dict NodeGroupId FlattenedAudio, List JE.Value )
reconcileExistingAudio nodeGroupId existing ( buckets, audioState, json ) =
    let
        key =
            audioKey existing
    in
    case Dict.get key buckets |> Maybe.andThen (extractMatch existing) of
        Just ( match, isExactMatch, rest ) ->
            let
                newBuckets =
                    if List.isEmpty rest then
                        Dict.remove key buckets

                    else
                        Dict.insert key rest buckets

                effects =
                    if isExactMatch then
                        -- Same buffer, same time, same settings: nothing to do.
                        []

                    else
                        changedSettings nodeGroupId existing match
            in
            ( newBuckets, Dict.insert nodeGroupId match audioState, effects ++ json )

        Nothing ->
            -- No new sound shares this sound's identity, so stop it.
            ( buckets, audioState, encodeStopSound nodeGroupId :: json )


{-| Pull the best match for `existing` out of a (non-empty) bucket: an exact
match if one is present (`isExactMatch = True`), otherwise the first sound in
the bucket. Returns the match, whether it was exact, and the rest of the bucket.
-}
extractMatch : FlattenedAudio -> List FlattenedAudio -> Maybe ( FlattenedAudio, Bool, List FlattenedAudio )
extractMatch existing bucket =
    case removeFirstEqual existing bucket of
        Just rest ->
            Just ( existing, True, rest )

        Nothing ->
            case bucket of
                first :: rest ->
                    Just ( first, False, rest )

                [] ->
                    Nothing


{-| The port messages needed to update an already-playing sound whose settings
changed. Only fields that actually differ produce a message.
-}
changedSettings : NodeGroupId -> FlattenedAudio -> FlattenedAudio -> List JE.Value
changedSettings nodeGroupId existing new =
    let
        changed getter encoder =
            if getter existing == getter new then
                Nothing

            else
                encoder nodeGroupId (getter new) |> Just
    in
    [ changed .volume encodeSetVolume
    , changed .loop encodeSetLoopConfig
    , changed .playbackRate encodeSetPlaybackRate
    , changed volumeTimelines encodeSetVolumeAt
    ]
        |> List.filterMap identity


startNewAudio :
    FlattenedAudio
    -> ( Int, Dict NodeGroupId FlattenedAudio, List JE.Value )
    -> ( Int, Dict NodeGroupId FlattenedAudio, List JE.Value )
startNewAudio audioLeft ( counter, audioState, json ) =
    ( counter + 1
    , Dict.insert counter audioLeft audioState
    , encodeStartSound counter audioLeft :: json
    )


{-| Remove the first element structurally equal to `target`, returning the list
without it (order preserved). `Nothing` when no element matches.
-}
removeFirstEqual : a -> List a -> Maybe (List a)
removeFirstEqual target list =
    removeFirstEqualHelp target [] list


removeFirstEqualHelp : a -> List a -> List a -> Maybe (List a)
removeFirstEqualHelp target skipped list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if x == target then
                Just (List.reverse skipped ++ xs)

            else
                removeFirstEqualHelp target (x :: skipped) xs


encodeStartSound : NodeGroupId -> FlattenedAudio -> JE.Value
encodeStartSound nodeGroupId audio_ =
    JE.object
        [ ( "action", JE.string "startSound" )
        , ( "nodeGroupId", JE.int nodeGroupId )
        , ( "bufferId", audioSourceBufferId audio_.source |> encodeBufferId )
        , ( "startTime", audioStartTime audio_ |> encodeTime )
        , ( "startAt", audio_.startAt |> encodeDuration )
        , ( "volume", JE.float audio_.volume )
        , ( "volumeTimelines", JE.list encodeVolumeTimeline (volumeTimelines audio_) )
        , ( "loop", encodeLoopConfig audio_.loop )
        , ( "playbackRate", JE.float audio_.playbackRate )
        ]


audioStartTime : FlattenedAudio -> Time.Posix
audioStartTime audio_ =
    Duration.addTo audio_.startTime audio_.offset


volumeTimelines : FlattenedAudio -> List VolumeTimeline
volumeTimelines audio_ =
    List.map
        (Nonempty.map (Tuple.mapFirst (\a -> Duration.addTo a audio_.offset)))
        audio_.volumeTimelines


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


{-| A nonempty list of (time, volume) points for defining how loud a sound should be at any point in time.
The points don't need to be sorted but you should avoid including multiple points that have the same time.
-}
type alias VolumeTimeline =
    Nonempty ( Time.Posix, Float )


encodeSetVolumeAt : NodeGroupId -> List VolumeTimeline -> JE.Value
encodeSetVolumeAt nodeGroupId volumeTimelines_ =
    JE.object
        [ ( "nodeGroupId", JE.int nodeGroupId )
        , ( "action", JE.string "setVolumeAt" )
        , ( "volumeAt", JE.list encodeVolumeTimeline volumeTimelines_ )
        ]


encodeVolumeTimeline : VolumeTimeline -> JE.Value
encodeVolumeTimeline volumeTimeline =
    volumeTimeline
        |> Nonempty.toList
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
            flattenedAudioCmd |> List.indexedMap (\index request -> ( model.requestCount + index, request ))
    in
    ( { model
        | requestCount = model.requestCount + List.length flattenedAudioCmd
        , pendingRequests = Dict.union model.pendingRequests (Dict.fromList newPendingRequests)
      }
        |> Model
    , newPendingRequests
        |> List.map (\( index, value ) -> encodeAudioLoadRequest index value)
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
    , offset : Duration
    , volume : Float
    , volumeTimelines : List (Nonempty ( Time.Posix, Float ))
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
              , offset = Quantity.zero
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

                Offset duration ->
                    List.map
                        (\a -> { a | offset = Quantity.plus duration a.offset })
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
    | ScaleVolumeAt { volumeAt : Nonempty ( Time.Posix, Float ) }
    | Offset Duration


{-| Audio data we can use to play sounds
-}
type Source
    = File { bufferId : BufferId }


audioSourceBufferId (File audioSource) =
    audioSource.bufferId


{-| Build a [`Source`](#Source) that refers to a given buffer id directly.

Normally a `Source` only comes from [`loadAudio`](#loadAudio), but the diffing
logic keys off nothing but the buffer id, so this exists so tests can construct
`Audio` values without loading real files. Not intended for application use.

-}
sourceWithBufferId : Int -> Source
sourceWithBufferId bufferId =
    File { bufferId = BufferId bufferId }


{-| Extra settings when playing audio from a file.

    -- Here we play a song at half speed and it skips the first 15 seconds of the song.
    audioWithConfig
        { loop = Nothing
        , playbackRate = 0.5
        , startAt = Duration.seconds 15
        }
        myCoolSong
        songStartTime

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


{-| Control how audio loops. `loopEnd` defines where (relative to the start of the audio) the audio should loop and `loopStart` defines where it should loop to.

    -- Here we have a song that plays an intro once and then loops between the 10 second point and the end of the song.
    let
        default =
            Audio.audioDefaultConfig

        -- We can use Audio.length to get the duration of coolBackgroundMusic but for simplicity it's hardcoded in this example
        songLength =
            Duration.seconds 120
    in
    audioWithConfig
        { default | loop = Just { loopStart = Duration.seconds 10, loopEnd = songLength } }
        coolBackgroundMusic
        startTime

-}
type alias LoopConfig =
    { loopStart : Duration, loopEnd : Duration }


{-| Play audio from an audio source at a given time. This is the same as using `audioWithConfig audioDefaultConfig`.

Note that in some browsers audio will be muted until the user interacts with the webpage.

-}
audio : Source -> Time.Posix -> Audio
audio source startTime =
    audioWithConfig audioDefaultConfig source startTime


{-| Play audio from an audio source at a given time with config.

Note that in some browsers audio will be muted until the user interacts with the webpage.

-}
audioWithConfig : PlayAudioConfig -> Source -> Time.Posix -> Audio
audioWithConfig audioSettings source startTime =
    BasicAudio { source = source, startTime = startTime, settings = audioSettings }


{-| Scale how loud a given `Audio` is.
1 preserves the current volume, 0.5 halves it, and 0 mutes it.
If the the volume is less than 0, 0 will be used instead.
-}
scaleVolume : Float -> Audio -> Audio
scaleVolume scaleBy audio_ =
    Effect { effectType = ScaleVolume { scaleBy = max 0 scaleBy }, audio = audio_ }


{-| Scale how loud some `Audio` is at different points in time.
The volume will transition linearly between those points.
The points in time don't need to be sorted but they need to be unique.

    import Audio
    import Duration
    import Time


    -- Here we define an audio function that fades in to full volume and then fades out until it's muted again.
    --
    --  1                ________
    --                 /         \
    --  0 ____________/           \_______
    --     t ->    fade in     fade out
    fadeInOut fadeInTime fadeOutTime audio =
        Audio.scaleVolumeAt
            [ ( Duration.subtractFrom fadeInTime Duration.second, 0 )
            , ( fadeInTime, 1 )
            , ( fadeOutTime, 1 )
            , ( Duration.addTo fadeOutTime Duration.second, 0 )
            ]
            audio

-}
scaleVolumeAt : List ( Time.Posix, Float ) -> Audio -> Audio
scaleVolumeAt volumeAt audio_ =
    Effect
        { effectType =
            ScaleVolumeAt
                { volumeAt =
                    volumeAt
                        |> Nonempty.fromList
                        |> Maybe.withDefault (Nonempty.fromElement ( Time.millisToPosix 0, 1 ))
                        |> Nonempty.map (Tuple.mapSecond (max 0))
                        |> Nonempty.sortBy (Tuple.first >> Time.posixToMillis)
                }
        , audio = audio_
        }


{-| Add an offset to the audio.

    import Audio
    import Duration

    delayByOneSecond audio =
        Audio.offsetBy Duration.second audio

-}
offsetBy : Duration -> Audio -> Audio
offsetBy offset_ audio_ =
    Effect
        { effectType = Offset offset_
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


{-| These are possible errors we can get when loading an audio source file.

  - FailedToDecode: This means we got the data but we couldn't decode it. One likely reason for this is that your url points to the wrong place and you're trying to decode a 404 page instead.
  - NetworkError: We couldn't reach the url. Either it's some kind of CORS issue, the server is down, or you're disconnected from the internet.
  - UnknownError: We don't know what happened but your audio didn't load!
  - ErrorThatHappensWhen...: Yes, there's a good reason for this. If you need to load more than 1000 sounds make an issue about it on github and I'll see what I can do.

-}
type LoadError
    = FailedToDecode
    | NetworkError
    | UnknownError
    | ErrorThatHappensWhenYouLoadMoreThan1000SoundsDueToHackyWorkAroundToMakeThisPackageBehaveMoreLikeAnEffectPackage


enumeratedResults : Nonempty (Result LoadError Source)
enumeratedResults =
    [ Err FailedToDecode, Err NetworkError, Err UnknownError ]
        ++ (List.range 0 1000 |> List.map (\bufferId -> { bufferId = BufferId bufferId } |> File |> Ok))
        |> Nonempty.Nonempty (Err ErrorThatHappensWhenYouLoadMoreThan1000SoundsDueToHackyWorkAroundToMakeThisPackageBehaveMoreLikeAnEffectPackage)


{-| Load audio from a url.
-}
loadAudio : (Result LoadError Source -> msg) -> String -> AudioCmd msg
loadAudio userMsg url =
    AudioLoadRequest
        { userMsg = Nonempty.map (\results -> ( results, userMsg results )) enumeratedResults
        , audioUrl = url
        }
