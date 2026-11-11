# elm-audio

This package explores the following question:

*What if we could play music and sound effects the same way we render HTML?*

To do that, elm-audio adds a `audio` field to your app. It looks something like this:
```elm
import Audio exposing (Audio, AudioData)
import Time

type alias Model = 
    { music : Audio.Source
    , musicStartTime : Time.Posix
    , soundOn : Bool
    }

audio : AudioData -> Model -> Audio
audio _ model =
    if model.soundOn then
        Audio.audio model.music model.musicStartTime
    else
        Audio.silence

{-
    Rest of the app...
-}

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

Notice that we don't need to write code to explicitly start and stop our music.
We just say what should be playing and when.
This is a lot like our view function, we don't say how our view should get updated, we just say what should appear.

## Getting Started

Make sure to install `ianmackenzie/elm-units` and `elm/time` as this package uses [`Duration`](https://package.elm-lang.org/packages/ianmackenzie/elm-units/latest/Duration#Duration) and [`Posix`](https://package.elm-lang.org/packages/elm/time/latest/Time#Posix).

Here is a simple [example app](https://ellie-app.com/nhNQDqZSNvha1) (source code is also [here](https://github.com/MartinSStewart/elm-audio/tree/master/example)) that's a good starting point if you want to begin making something with `elm-audio`.

If you want to see a more interesting use case, I rewrote the audio system in [elm-mogee](https://github.com/MartinSStewart/elm-mogee/tree/elm-audio) to use `elm-audio` (this uses an older version of elm-audio so the API won't exactly match).

## JS Setup

The following ports must be defined.

```elm
-- The ports must have these specific names.
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
function startAudio(e){if(window.AudioContext=window.AudioContext||window.webkitAudioContext||!1,window.AudioContext){let l=[],u=new AudioContext,i={};async function o(o){let t;try{const e=await fetch(o.audioUrl);t=await e.arrayBuffer()}catch{return void e.ports.audioPortFromJS.send({type:0,requestId:o.requestId,error:"NetworkError"})}try{const n=await u.decodeAudioData(t);let a=l.length;l.push(n),e.ports.audioPortFromJS.send({type:1,requestId:o.requestId,bufferId:a,durationInSeconds:n.length/n.sampleRate})}catch(t){e.ports.audioPortFromJS.send({type:0,requestId:o.requestId,error:t.message})}}function t(e,o){return(e-o)/1e3+u.currentTime}function n(e,o){o?(e.loopStart=o.loopStart/1e3,e.loopEnd=o.loopEnd/1e3,e.loop=!0):e.loop=!1}function a(e,o,t,n,a){let r=(a-e)/(t-e);return Number.isFinite(r)?r*(n-o)+o:o}function r(e,o){return e.map((e=>{let n=u.createGain();n.gain.setValueAtTime(e[0].volume,0),n.gain.linearRampToValueAtTime(e[0].volume,0);let r=t(o,o);for(let s=1;s<e.length;s++){let d=e[s-1],l=t(d.time,o),u=e[s],i=t(u.time,o);if(i>r&&r>=l){let e=a(l,d.volume,i,u.volume,r);n.gain.setValueAtTime(e,0),n.gain.linearRampToValueAtTime(u.volume,i)}else i>r?n.gain.linearRampToValueAtTime(u.volume,i):n.gain.setValueAtTime(u.volume,0)}return n}))}function s(e){for(let o=1;o<e.length;o++)e[o-1].connect(e[o])}function d(e,o,a,d,l,i,c,p,m){let f=u.createBufferSource();if(c){let o=10+c.loopEnd/1e3-e.length/e.sampleRate;if(o>0){let t=e.getChannelData(0).length+Math.ceil(o*e.sampleRate),n=u.createBuffer(e.numberOfChannels,t,u.sampleRate);for(let o=0;o<e.numberOfChannels;o++)n.copyToChannel(e.getChannelData(o),o);f.buffer=n}else f.buffer=e}else f.buffer=e;f.playbackRate.value=p,n(f,c);let b=r(a,i),A=u.createGain();A.gain.setValueAtTime(o,0);let g=u.createStereoPanner();if(g.pan.setValueAtTime(m??0,0),s([f,A,g,...b,u.destination]),d>=i)f.start(t(d,i),l/1e3);else{let e=(i-d)/1e3;f.start(0,e+l/1e3)}return{sourceNode:f,gainNode:A,pannerNode:g,volumeAtGainNodes:b}}e.ports.audioPortFromJS.send({type:2,samplesPerSecond:u.sampleRate}),e.ports.audioPortToJS.subscribe((async e=>{let t=(new Date).getTime();for(let o=0;o<e.audio.length;o++){let a=e.audio[o];switch(a.action){case"stopSound":{let e=i[a.nodeGroupId];delete i[a.nodeGroupId],e.nodes.sourceNode.stop(),e.nodes.sourceNode.disconnect(),e.nodes.gainNode.disconnect(),e.nodes.pannerNode.disconnect(),e.nodes.volumeAtGainNodes.map((e=>e.disconnect()));break}case"setVolume":i[a.nodeGroupId].nodes.gainNode.gain.setValueAtTime(a.volume,0);break;case"setVolumeAt":{let e=i[a.nodeGroupId];e.nodes.volumeAtGainNodes.map((e=>e.disconnect())),e.nodes.pannerNode.disconnect();let o=r(a.volumeAt,t);s([e.nodes.pannerNode,...o,u.destination]),e.nodes.volumeAtGainNodes=o;break}case"setLoopConfig":n(i[a.nodeGroupId].nodes.sourceNode,a.loop);break;case"setPlaybackRate":i[a.nodeGroupId].nodes.sourceNode.playbackRate.setValueAtTime(a.playbackRate,0);break;case"setPan":i[a.nodeGroupId].nodes.pannerNode.pan.setValueAtTime(a.pan,0);break;case"startSound":{let e=d(l[a.bufferId],a.volume,a.volumeTimelines,a.startTime,a.startAt,t,a.loop,a.playbackRate,a.pan);i[a.nodeGroupId]={bufferId:a.bufferId,nodes:e};break}}}const a=e.audioCmds.map(o);await Promise.all(a)}))}else console.log("Web audio is not supported in your browser.")}
```
Unminified version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/master/src/audio.js).