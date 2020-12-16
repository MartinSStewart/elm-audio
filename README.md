# elm-audio

This package explores the following question:

*What if we could play music and sound effects the same way we render HTML?*

To do that, elm-audio adds a `audio` field to your app. It looks something like this:
```elm
audio : AudioData -> Model -> Audio
audio _ model =
    if model.soundOn then
        Audio.audio model.music model.musicStartTime
    else
        Audio.silence

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

Make sure you install `ianmackenzie/elm-units` and `elm/time` as this package uses [`Duration`](https://package.elm-lang.org/packages/ianmackenzie/elm-units/latest/Duration#Duration) and [`Posix`](https://package.elm-lang.org/packages/elm/time/latest/Time#Posix) throughout the API.

Here is a simple [example app](https://ellie-app.com/bPKQ4BLCtFKa1) (source code is also [here](https://github.com/MartinSStewart/elm-audio/tree/master/example)) that's a good starting point if you want to begin making something with `elm-audio`.

If you want to see a more interesting use case, I rewrote the audio system in [elm-mogee](https://github.com/MartinSStewart/elm-mogee/tree/elm-audio) to use `elm-audio`.

### JS Setup

The following ports must be defined.

```elm
-- The ports must have these specifc names.
port audioPortToJS : Json.Encode.Value -> Cmd msg
port audioPortFromJS : (Json.Decode.Value -> msg) -> Sub msg

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

Then you'll need to copy the following JS code into your program and then call `startAudio(myElmApp);` (look at the [example app](https://github.com/MartinSStewart/elm-audio/blob/master/example/index.html) if you're not sure about this).

```javascript
function startAudio(e){if(window.AudioContext=window.AudioContext||window.webkitAudioContext||!1,window.AudioContext){let u=[],s=new AudioContext,d={},l=528;function o(o,t){let n=new XMLHttpRequest;n.open("GET",o,!0),n.responseType="arraybuffer",n.onerror=function(){e.ports.audioPortFromJS.send({type:0,requestId:t,error:"NetworkError"})},n.onload=function(){s.decodeAudioData(n.response,function(n){let r=u.length,a=o.endsWith(".mp3");u.push({isMp3:a,buffer:n}),e.ports.audioPortFromJS.send({type:1,requestId:t,bufferId:r,durationInSeconds:(n.length-(a?l:0))/n.sampleRate})},function(o){e.ports.audioPortFromJS.send({type:0,requestId:t,error:o.message})})},n.send()}function t(e,o){return(e-o)/1e3+s.currentTime}function n(e,o,t){o?(e.loopStart=t+o.loopStart/1e3,e.loopEnd=t+o.loopEnd/1e3,e.loop=!0):e.loop=!1}function r(e,o){return e.map(e=>{let n=s.createGain();n.gain.setValueAtTime(e[0].volume,0),n.gain.linearRampToValueAtTime(e[0].volume,t(e[0].time,o));for(let r=1;r<e.length;r++){let a=e[r],i=e[r-1],u=t(a.time,o);if(u>=s.currentTime&&i.contextTime<s.currentTime){let e=(s.currentTime-i.contextTime)/(u-i.contextTime)*(a.volume-i.volume)+i.volume;isFinite(e)&&n.gain.setValueAtTime(e,0)}else u>=s.currentTime?n.gain.linearRampToValueAtTime(a.volume,u):n.gain.setValueAtTime(a.volume,0);i={contextTime:u,volume:a.volume}}return n})}function a(e){for(let o=1;o<e.length;o++)e[o-1].connect(e[o])}function i(e,o,i,u,d,m,c,p){let f=e.buffer,b=e.isMp3?l/s.sampleRate:0,T=s.createBufferSource();T.buffer=f,T.playbackRate.value=p,n(T,c,b);let g=r(i,m),A=s.createGain();if(A.gain.setValueAtTime(o,0),a([T,A,...g,s.destination]),u>=m)T.start(t(u,m),b+d/1e3);else{let e=(m-u)/1e3;T.start(0,e+b+d/1e3)}return{sourceNode:T,gainNode:A,volumeAtGainNodes:g}}e.ports.audioPortFromJS.send({type:2,samplesPerSecond:s.sampleRate}),e.ports.audioPortToJS.subscribe(e=>{let t=(new Date).getTime();for(let o=0;o<e.audio.length;o++){let m=e.audio[o];switch(m.action){case"stopSound":{let e=d[m.nodeGroupId];d[m.nodeGroupId]=null,e.nodes.sourceNode.stop(),e.nodes.sourceNode.disconnect(),e.nodes.gainNode.disconnect(),e.nodes.volumeAtGainNodes.map(e=>e.disconnect());break}case"setVolume":d[m.nodeGroupId].nodes.gainNode.gain.setValueAtTime(m.volume,0);break;case"setVolumeAt":{let e=d[m.nodeGroupId];e.nodes.volumeAtGainNodes.map(e=>e.disconnect()),e.nodes.gainNode.disconnect();let o=r(m.volumeAt,t);a([e.nodes.gainNode,...o,s.destination]),e.nodes.volumeAtGainNodes=o;break}case"setLoopConfig":{let e=d[m.nodeGroupId],o=u[e.bufferId].isMp3?l/s.sampleRate:0;n(e.nodes.sourceNode,e.loop,o);break}case"setPlaybackRate":d[m.nodeGroupId].nodes.sourceNode.playbackRate.setValueAtTime(m.playbackRate,0);break;case"startSound":{let e=i(u[m.bufferId],m.volume,m.volumeTimelines,m.startTime,m.startAt,t,m.loop,m.playbackRate);d[m.nodeGroupId]={bufferId:m.bufferId,nodes:e};break}}}for(let t=0;t<e.audioCmds.length;t++)o(e.audioCmds[t].audioUrl,e.audioCmds[t].requestId)})}else console.log("Web audio is not supported in your browser.")}
```
Unminified version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/master/src/audio.js).