# elm-audio

This package explores the following question:

*What if we could play music and sound effects the same way we render HTML?*

To do that, elm-audio adds a `audio` field to your app. It looks something like this:
```elm
audio : Model -> Audio
audio model =
    if model.soundOn then
        Audio.audio model.music model.musicStartTime
    else
        Audio.silence

main : Audio.Program flags Model Msg
main = 
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , audio = audio
        -- Since this is a normal Elm package we need ports to make this all work
        , audioPorts = audioPorts
        }
```

Notice that we don't need to write code to explicitly start and stop our music. We just say what should be playing and when.

### Getting Started

Here is a simple [example app](https://github.com/MartinSStewart/elm-audio/tree/master/example) that's a good starting point if you want to begin making something with `elm-audio`.

If you want to see a more interesting use case, I rewrote the audio system in [elm-mogee](https://github.com/MartinSStewart/elm-mogee/tree/elm-audio) to use `elm-audio`.


### JS Setup

The following ports must be defined and passed into `Audio.Program`.

```elm
port audioPortToJS : Json.Encode.Value -> Cmd msg
port audioPortFromJS : (Json.Decode.Value -> msg) -> Sub msg

main : Audio.Program flags Model Msg
main = 
    Audio.elementWithAudio
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , audio = audio
        , audioPort = { toJS = audioPortToJS, fromJS = audioPortFromJS }
        }
```

Then you'll need to copy the following JS code into your program and then call `startAudio(myElmApp);` (look at the [example app](https://github.com/MartinSStewart/elm-audio/tree/master/example) if you're not sure about this).

```javascript
function startAudio(app)
{
    window.AudioContext = window.AudioContext || window.webkitAudioContext || false;
    if (window.AudioContext) {
        let audioBuffers = []
        let context = new AudioContext();
        let audioPlaying = {};
        /* https://lame.sourceforge.io/tech-FAQ.txt
         * "All *decoders* I have tested introduce a delay of 528 samples. That
         * is, after decoding an mp3 file, the output will have 528 samples of
         * 0's appended to the front."
         */
        let mp3MarginInSamples = 528;

        app.ports.audioPortFromJS.send({ type: 2, samplesPerSecond: context.sampleRate });

        function loadAudio(audioUrl, requestId) {
            let request = new XMLHttpRequest();
            request.open('GET', audioUrl, true);

            request.responseType = 'arraybuffer';

            request.onerror = function() {
                app.ports.audioPortFromJS.send({ type: 0, requestId: requestId, error: "NetworkError" });
            }

            // Decode asynchronously
            request.onload = function() {
                context.decodeAudioData(request.response, function(buffer) {
                    let bufferId = audioBuffers.length;

                    let isMp3 = audioUrl.endsWith(".mp3");
                    // TODO: Read the header of the ArrayBuffer before decoding to an AudioBuffer https://www.mp3-tech.org/programmer/frame_header.html
                    // need to use DataViews to read from the ArrayBuffer
                    audioBuffers.push({ isMp3: isMp3, buffer: buffer });

                    app.ports.audioPortFromJS.send({
                        type: 1,
                        requestId: requestId,
                        bufferId: bufferId,
                        durationInSeconds: (buffer.length - (isMp3 ? mp3MarginInSamples : 0)) / buffer.sampleRate
                    });
                }, function(error) {
                    app.ports.audioPortFromJS.send({ type: 0, requestId: requestId, error: error.message });
                });
            }
            request.send();
        }

        function posixToContextTime(posix, currentTimePosix) {
            return (posix - currentTimePosix) / 1000 + context.currentTime;
        }

        function setLoop(sourceNode, loop, mp3MarginInSeconds) {
            if (loop) {
                sourceNode.loopStart = mp3MarginInSeconds + loop.loopStart / 1000;
                sourceNode.loopEnd = mp3MarginInSeconds + loop.loopEnd / 1000;
                sourceNode.loop = true;
            }
            else {
                sourceNode.loop = false;
            }
        }

        function createVolumeTimelineGainNodes(volumeAt, currentTime) {
            return volumeAt.map(volumeTimeline => {
                let gainNode = context.createGain();

                gainNode.gain.setValueAtTime(volumeTimeline[0].volume, 0);
                gainNode.gain.linearRampToValueAtTime(
                    volumeTimeline[0].volume,
                    posixToContextTime(volumeTimeline[0].time, currentTime));

                for (let j = 1; j < volumeTimeline.length; j++) {
                    let timeAndValue = volumeTimeline[j];
                    let previous = volumeTimeline[j-1];
                    let contextTime = posixToContextTime(timeAndValue.time, currentTime);
                    if (contextTime >= context.currentTime && previous.contextTime < context.currentTime) {
                        let t = (context.currentTime - previous.contextTime) / (contextTime - previous.contextTime);
                        let volume = t * (timeAndValue.volume - previous.volume) + previous.volume;

                        if (isFinite(volume)) {
                            gainNode.gain.setValueAtTime(volume, 0);
                        }
                    }
                    else if (contextTime >= context.currentTime) {
                        gainNode.gain.linearRampToValueAtTime(timeAndValue.volume, contextTime);
                    }
                    else {
                        gainNode.gain.setValueAtTime(timeAndValue.volume, 0);
                    }
                    previous = { contextTime: contextTime, volume: timeAndValue.volume };
                }

                return gainNode;
            });
        }

        function connectNodes(nodes) {
            for (let j = 1; j < nodes.length; j++) {
                nodes[j-1].connect(nodes[j]);
            }
        }

        function playSound(audioBuffer, volume, volumeTimelines, startTime, startAt, currentTime, loop, playbackRate) {
            let buffer = audioBuffer.buffer;
            let mp3MarginInSeconds = audioBuffer.isMp3
                ? mp3MarginInSamples / context.sampleRate
                : 0;
            let source = context.createBufferSource();
            source.buffer = buffer;
            source.playbackRate.value = playbackRate;
            setLoop(source, loop, mp3MarginInSeconds);

            let timelineGainNodes = createVolumeTimelineGainNodes(volumeTimelines, currentTime);

            let gainNode = context.createGain();
            gainNode.gain.setValueAtTime(volume, 0);

            connectNodes([source, gainNode, ...timelineGainNodes, context.destination]);

            if (startTime >= currentTime) {
                source.start(posixToContextTime(startTime, currentTime), mp3MarginInSeconds + startAt / 1000);
            }
            else {
                // TODO: offset should account for looping
                let offset = (currentTime - startTime) / 1000;
                source.start(0, offset + mp3MarginInSeconds + startAt / 1000);
            }

            return { sourceNode: source, gainNode: gainNode, volumeAtGainNodes: timelineGainNodes };
        }

        app.ports.audioPortToJS.subscribe( ( message ) => {
            let currentTime = new Date().getTime();
            for (let i = 0; i < message.audio.length; i++) {
                let audio = message.audio[i];
                switch (audio.action)
                {
                    case "stopSound":
                    {
                        let value = audioPlaying[audio.nodeGroupId];
                        audioPlaying[audio.nodeGroupId] = null;
                        value.nodes.sourceNode.stop();
                        value.nodes.sourceNode.disconnect();
                        value.nodes.gainNode.disconnect();
                        value.nodes.volumeAtGainNodes.map(node => node.disconnect());
                        break;
                    }
                    case "setVolume":
                    {
                        let value = audioPlaying[audio.nodeGroupId];
                        value.nodes.gainNode.gain.setValueAtTime(audio.volume, 0);
                        break;
                    }
                    case "setVolumeAt":
                    {
                        let value = audioPlaying[audio.nodeGroupId];
                        value.nodes.volumeAtGainNodes.map(node => node.disconnect());
                        value.nodes.gainNode.disconnect();

                        let newGainNodes = createVolumeTimelineGainNodes(audio.volumeAt, currentTime);

                        connectNodes([value.nodes.gainNode, ...newGainNodes, context.destination]);

                        value.nodes.volumeAtGainNodes = newGainNodes;
                        break;
                    }
                    case "setLoopConfig":
                    {
                        let value = audioPlaying[audio.nodeGroupId];
                        let audioBuffer = audioBuffers[value.bufferId];
                        let mp3MarginInSeconds = audioBuffer.isMp3
                            ? mp3MarginInSamples / context.sampleRate
                            : 0;
                        setLoop(value.nodes.sourceNode, value.loop, mp3MarginInSeconds);
                        break;
                    }
                    case "setPlaybackRate":
                    {
                        let value = audioPlaying[audio.nodeGroupId];
                        value.nodes.sourceNode.playbackRate.setValueAtTime(audio.playbackRate, 0);
                        break;
                    }
                    case "startSound":
                    {
                        let nodes = playSound(
                            audioBuffers[audio.bufferId],
                            audio.volume,
                            audio.volumeTimelines,
                            audio.startTime,
                            audio.startAt,
                            currentTime,
                            audio.loop,
                            audio.playbackRate);
                        audioPlaying[audio.nodeGroupId] = { bufferId: audio.bufferId, nodes: nodes };
                        break;
                    }
                }
            }

            for (let i = 0; i < message.audioCmds.length; i++) {
                loadAudio(message.audioCmds[i].audioUrl, message.audioCmds[i].requestId);
            }
        });
    }
    else {
        console.log("Web audio is not supported in your browser.");
    }
}
```