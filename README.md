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
function startAudio(e){if(window.AudioContext=window.AudioContext||window.webkitAudioContext||!1,window.AudioContext){let o=[],t=new AudioContext,n={};function a(n,a){let r=new XMLHttpRequest;r.open("GET",n,!0),r.responseType="arraybuffer",r.onerror=function(){e.ports.audioPortFromJS.send({type:0,requestId:a,error:"NetworkError"})},r.onload=function(){t.decodeAudioData(r.response,function(t){let r=o.length,s=n.endsWith(".mp3");o.push({isMp3:s,buffer:t}),e.ports.audioPortFromJS.send({type:1,requestId:a,bufferId:r,durationInSeconds:(t.length-0)/t.sampleRate})},function(o){e.ports.audioPortFromJS.send({type:0,requestId:a,error:o.message})})},r.send()}function r(e,o){return(e-o)/1e3+t.currentTime}function s(e,o,t){o?(e.loopStart=t+o.loopStart/1e3,e.loopEnd=t+o.loopEnd/1e3,e.loop=!0):e.loop=!1}function u(e,o,t,n,a){let r=(a-e)/(t-e);return Number.isFinite(r)?r*(n-o)+o:o}function l(e,o){return e.map(e=>{let n=t.createGain();n.gain.setValueAtTime(e[0].volume,0),n.gain.linearRampToValueAtTime(e[0].volume,0);let a=r(o,o);for(let s=1;s<e.length;s+=1){let l=e[s-1],i=r(l.time,o),d=e[s],p=r(d.time,o);if(p>a&&a>=i){let m=u(i,l.volume,p,d.volume,a);n.gain.setValueAtTime(m,0),n.gain.linearRampToValueAtTime(d.volume,p)}else p>a?n.gain.linearRampToValueAtTime(d.volume,p):n.gain.setValueAtTime(d.volume,0)}return n})}function i(e){for(let o=1;o<e.length;o+=1)e[o-1].connect(e[o])}function d(e,o,n,a,u,d,p,m){let c=e.buffer,f=e.isMp3?0/t.sampleRate:0,$=t.createBufferSource();if(p){let b=10+p.loopEnd/1e3-c.length/c.sampleRate;if(b>0){let g=c.getChannelData(0).length+Math.ceil(b*c.sampleRate),A=t.createBuffer(c.numberOfChannels,g,t.sampleRate);for(let T=0;T<c.numberOfChannels;T+=1)A.copyToChannel(c.getChannelData(T),T);$.buffer=A}else $.buffer=c}else $.buffer=c;$.playbackRate.value=m,s($,p,f);let _=l(n,d),I=t.createGain();return I.gain.setValueAtTime(o,0),i([$,I,..._,t.destination]),a>=d?$.start(r(a,d),f+u/1e3):$.start(0,(d-a)/1e3+f+u/1e3),{sourceNode:$,gainNode:I,volumeAtGainNodes:_}}e.ports.audioPortFromJS.send({type:2,samplesPerSecond:t.sampleRate}),e.ports.audioPortToJS.subscribe(e=>{let r=new Date().getTime();for(let u=0;u<e.audio.length;u+=1){let p=e.audio[u];switch(p.action){case"stopSound":{let m=n[p.nodeGroupId];n[p.nodeGroupId]=null,m.nodes.sourceNode.stop(),m.nodes.sourceNode.disconnect(),m.nodes.gainNode.disconnect(),m.nodes.volumeAtGainNodes.map(e=>e.disconnect());break}case"setVolume":n[p.nodeGroupId].nodes.gainNode.gain.setValueAtTime(p.volume,0);break;case"setVolumeAt":{let c=n[p.nodeGroupId];c.nodes.volumeAtGainNodes.map(e=>e.disconnect()),c.nodes.gainNode.disconnect();let f=l(p.volumeAt,r);i([c.nodes.gainNode,...f,t.destination]),c.nodes.volumeAtGainNodes=f;break}case"setLoopConfig":{let $=n[p.nodeGroupId],b=o[$.bufferId].isMp3?0/t.sampleRate:0;s($.nodes.sourceNode,p.loop,b);break}case"setPlaybackRate":n[p.nodeGroupId].nodes.sourceNode.playbackRate.setValueAtTime(p.playbackRate,0);break;case"startSound":{let g=d(o[p.bufferId],p.volume,p.volumeTimelines,p.startTime,p.startAt,r,p.loop,p.playbackRate);n[p.nodeGroupId]={bufferId:p.bufferId,nodes:g}}}}for(let A=0;A<e.audioCmds.length;A+=1)a(e.audioCmds[A].audioUrl,e.audioCmds[A].requestId)})}else console.log("Web audio is not supported in your browser.")}
```
Unminified version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/master/src/audio.js).