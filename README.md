# elm-audio

### JS Setup

In order for this package to work correctly, you'll need to copy the following JS code into your program and then call `startAudio(myElmApp);`
```
function startAudio(app)
{
    window.AudioContext = window.AudioContext || window.webkitAudioContext || false;
    if (window.AudioContext) {
        let audioBuffers = []
        let context = new AudioContext();
        let bufferSources = [];
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
                    // Read the header of the ArrayBuffer before decoding to an AudioBuffer https://www.mp3-tech.org/programmer/frame_header.html
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

        function playSound(audioBuffer, volume, startTime, currentTime, contextTime) {
            let buffer = audioBuffer.buffer;
            let mp3MarginInSeconds = audioBuffer.isMp3
                ? mp3MarginInSamples / buffer.sampleRate
                : 0;
            let source = context.createBufferSource();
            source.buffer = buffer;

            let gainNode = context.createGain();
            source.connect(gainNode);
            gainNode.connect(context.destination);

            if (startTime >= currentTime) {
                let startTime_ = (startTime - currentTime) / 1000
                source.start(startTime_ + contextTime, mp3MarginInSeconds);
            }
            else {
                let offset = (currentTime - startTime) / 1000
                source.start(0, offset + mp3MarginInSeconds);
            }

            return { sourceNode: source, gainNode: gainNode };
        }

        app.ports.audioPortToJS.subscribe( ( message ) => {
            let currentTime = new Date().getTime();
            let contextTime = context.currentTime;
            for (let i = 0; i < message.audio.length; i++) {
                let audio = message.audio[i];
                switch (audio.action)
                {
                    case "stopSound":
                    {
                        let index = bufferSources.findIndex(value => value.bufferId === audio.bufferId);
                        let value = bufferSources[index];
                        bufferSources.splice(index, 1);
                        value.nodes.sourceNode.stop();
                        value.nodes.sourceNode.disconnect();
                        value.nodes.gainNode.disconnect();
                        break;
                    }
                    case "startSound":
                    {
                        let nodes = playSound(
                            audioBuffers[audio.bufferId],
                            1,
                            audio.startTime,
                            currentTime,
                            contextTime);
                        bufferSources.push({ bufferId: audio.bufferId, nodes: nodes });
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