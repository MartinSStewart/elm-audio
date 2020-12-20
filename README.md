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

Here is a simple [example app](https://ellie-app.com/bR446t24kqWa1) (source code is also [here](https://github.com/MartinSStewart/elm-audio/tree/master/example)) that's a good starting point if you want to begin making something with `elm-audio`.

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
function startAudio(e){if(window.AudioContext=window.AudioContext||window.webkitAudioContext||!1,window.AudioContext){let s=[],d=new AudioContext,l={},p=0;function o(o,t){let n=new XMLHttpRequest;n.open("GET",o,!0),n.responseType="arraybuffer",n.onerror=function(){e.ports.audioPortFromJS.send({type:0,requestId:t,error:"NetworkError"})},n.onload=function(){d.decodeAudioData(n.response,function(n){let a=s.length,r=o.endsWith(".mp3");s.push({isMp3:r,buffer:n}),e.ports.audioPortFromJS.send({type:1,requestId:t,bufferId:a,durationInSeconds:(n.length-(r?p:0))/n.sampleRate})},function(o){e.ports.audioPortFromJS.send({type:0,requestId:t,error:o.message})})},n.send()}function t(e,o){return(e-o)/1e3+d.currentTime}function n(e,o,t){o?(e.loopStart=t+o.loopStart/1e3,e.loopEnd=t+o.loopEnd/1e3,e.loop=!0):e.loop=!1}function a(e,o,t,n,a){let r=(a-e)/(t-e);return Number.isFinite(r)?r*(n-o)+o:o}function r(e,o){return e.map(e=>{let n=d.createGain();n.gain.setValueAtTime(e[0].volume,0),n.gain.linearRampToValueAtTime(e[0].volume,0);let r=t(o,o);for(let u=1;u<e.length;u++){let i=e[u-1],s=t(i.time,o),d=e[u],l=t(d.time,o);if(l>r&&r>=s){let e=a(s,i.volume,l,d.volume,r);n.gain.setValueAtTime(e,0),n.gain.linearRampToValueAtTime(d.volume,l)}else l>r?n.gain.linearRampToValueAtTime(d.volume,l):n.gain.setValueAtTime(d.volume,0)}return n})}function u(e){for(let o=1;o<e.length;o++)e[o-1].connect(e[o])}function i(e,o,a,i,s,l,m,c){let f=e.buffer,b=e.isMp3?p/d.sampleRate:0,g=d.createBufferSource();g.buffer=f,g.playbackRate.value=c,n(g,m,b);let A=r(a,l),T=d.createGain();if(T.gain.setValueAtTime(o,0),u([g,T,...A,d.destination]),i>=l)g.start(t(i,l),b+s/1e3);else{let e=(l-i)/1e3;g.start(0,e+b+s/1e3)}return{sourceNode:g,gainNode:T,volumeAtGainNodes:A}}e.ports.audioPortFromJS.send({type:2,samplesPerSecond:d.sampleRate}),e.ports.audioPortToJS.subscribe(e=>{let t=(new Date).getTime();for(let o=0;o<e.audio.length;o++){let a=e.audio[o];switch(a.action){case"stopSound":{let e=l[a.nodeGroupId];l[a.nodeGroupId]=null,e.nodes.sourceNode.stop(),e.nodes.sourceNode.disconnect(),e.nodes.gainNode.disconnect(),e.nodes.volumeAtGainNodes.map(e=>e.disconnect());break}case"setVolume":l[a.nodeGroupId].nodes.gainNode.gain.setValueAtTime(a.volume,0);break;case"setVolumeAt":{let e=l[a.nodeGroupId];e.nodes.volumeAtGainNodes.map(e=>e.disconnect()),e.nodes.gainNode.disconnect();let o=r(a.volumeAt,t);u([e.nodes.gainNode,...o,d.destination]),e.nodes.volumeAtGainNodes=o;break}case"setLoopConfig":{let e=l[a.nodeGroupId],o=s[e.bufferId].isMp3?p/d.sampleRate:0;n(e.nodes.sourceNode,e.loop,o);break}case"setPlaybackRate":l[a.nodeGroupId].nodes.sourceNode.playbackRate.setValueAtTime(a.playbackRate,0);break;case"startSound":{let e=i(s[a.bufferId],a.volume,a.volumeTimelines,a.startTime,a.startAt,t,a.loop,a.playbackRate);l[a.nodeGroupId]={bufferId:a.bufferId,nodes:e};break}}}for(let t=0;t<e.audioCmds.length;t++)o(e.audioCmds[t].audioUrl,e.audioCmds[t].requestId)})}else console.log("Web audio is not supported in your browser.")}
```
Unminified version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/89147e416dc9ac29333d61b8b96851c0641684cb/src/audio.js).