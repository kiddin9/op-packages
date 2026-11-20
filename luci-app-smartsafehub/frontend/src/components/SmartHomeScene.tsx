// SPDX-License-Identifier: GPL-3.0-or-later
/** Purely decorative, lightweight SVG. Never represents a real device or live status. */
export function SmartHomeScene() {
  return <div class="ssh-home-scene" aria-hidden="true">
    <div class="ssh-home-scene-grid" />
    <svg class="ssh-home-scene-svg" viewBox="0 0 520 340" focusable="false" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="ssh-home-lamp-glow">
          <stop offset="0%" style="stop-color:#fcd889;stop-opacity:0.62" />
          <stop offset="45%" style="stop-color:#14b8a6;stop-opacity:0.18" />
          <stop offset="100%" style="stop-color:#14b8a6;stop-opacity:0" />
        </radialGradient>
        <linearGradient id="ssh-home-device" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" style="stop-color:#263e59" />
          <stop offset="100%" style="stop-color:#0e192d" />
        </linearGradient>
        <linearGradient id="ssh-home-bulb" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" style="stop-color:#fff6ce" />
          <stop offset="100%" style="stop-color:#ffc972" />
        </linearGradient>
      </defs>

      <ellipse cx="260" cy="297" rx="177" ry="23" fill="#0d9488" opacity="0.11" />
      <path d="M115 180 260 62 405 180" fill="none" stroke="#5eead4" strokeOpacity=".19" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M151 159 V254 Q151 273 173 273 H347 Q369 273 369 254 V159" fill="none" stroke="#5eead4" strokeOpacity=".10" strokeWidth="2" />
      <path d="M260 65 V93" stroke="#f0dfa4" strokeOpacity=".45" strokeWidth="2" strokeLinecap="round" />
      <g class="ssh-home-light-float">
        <circle class="ssh-home-light-glow" cx="260" cy="144" r="99" fill="url(#ssh-home-lamp-glow)" />
        <path d="M260 103 C236 103 219 121 219 143 C219 159 228 168 236 178 Q240 184 240 190 H280 Q280 184 284 178 C293 168 301 159 301 143 C301 121 284 103 260 103Z"
          fill="url(#ssh-home-bulb)" stroke="#ffe5aa" strokeWidth="2" />
        <path d="M242 141 C242 130 249 121 261 120" fill="none" stroke="#fff9e9" strokeWidth="5" strokeOpacity=".65" strokeLinecap="round" />
        <rect x="241" y="188" width="38" height="9" rx="4" fill="#a7b7c9" />
        <rect x="244" y="198" width="32" height="8" rx="4" fill="#7e9bb0" />
        <path d="M252 207 H268 L264 212 H256Z" fill="#5eead4" />
      </g>

      <g class="ssh-home-signal" fill="none" stroke="#5eead4" strokeWidth="2.1" strokeLinecap="round">
        <path d="M206 219 Q260 184 314 219" strokeOpacity=".72" />
        <path d="M221 230 Q260 203 299 230" strokeOpacity=".58" />
        <path d="M236 240 Q260 223 284 240" strokeOpacity=".50" />
      </g>
      <g class="ssh-home-orbit-left">
        <circle cx="100" cy="165" r="34" fill="#132b3c" stroke="#2dd4bf" strokeOpacity=".42" />
        <path d="M89 167 100 157 111 167 V178 H89Z" fill="none" stroke="#99f6e4" strokeWidth="2.5" strokeLinejoin="round" />
        <path d="M97 178 V169 H103 V178" fill="none" stroke="#99f6e4" strokeWidth="2" />
      </g>
      <g class="ssh-home-orbit-right">
        <circle cx="420" cy="169" r="34" fill="#132b3c" stroke="#2dd4bf" strokeOpacity=".42" />
        <path d="M420 151 A13 13 0 0 0 407 164 C407 175 420 187 420 187 S433 175 433 164 A13 13 0 0 0 420 151Z" fill="none" stroke="#99f6e4" strokeWidth="2.5" />
        <circle cx="420" cy="164" r="4" fill="#5eead4" />
      </g>
      <path d="M134 171 Q165 179 188 204 M386 204 Q399 183 387 172" fill="none" stroke="#2dd4bf" strokeOpacity=".45" strokeWidth="2" strokeDasharray="4 8" strokeLinecap="round" />
      <g class="ssh-home-hub-float">
        <rect x="173" y="245" width="174" height="62" rx="21" fill="#020617" opacity=".30" />
        <rect x="169" y="239" width="182" height="61" rx="19" fill="url(#ssh-home-device)" stroke="#5eead4" strokeOpacity=".55" />
        <path d="M191 255 H329" stroke="#9cc6cf" strokeOpacity=".16" strokeLinecap="round" />
        <circle cx="202" cy="270" r="6" fill="#2dd4bf" />
        <circle class="ssh-home-hub-led" cx="202" cy="270" r="13" fill="#2dd4bf" opacity=".17" />
        <text x="260" y="274" fill="#e2f9f6" fontFamily="system-ui, sans-serif" fontSize="12" fontWeight="800" letterSpacing="2" textAnchor="middle">JARBIS</text>
        <circle cx="321" cy="270" r="2.5" fill="#99f6e4" />
        <circle cx="332" cy="270" r="2.5" fill="#5eead4" opacity=".48" />
      </g>
      <g class="ssh-home-sparkle">
        <path d="M173 111 v-14 m-7 7 h14" stroke="#a5f3fc" strokeWidth="2" strokeLinecap="round" />
        <circle cx="361" cy="101" r="3" fill="#fcd34d" />
        <circle cx="143" cy="236" r="3" fill="#5eead4" />
        <path d="M386 239 v-10 m-5 5 h10" stroke="#a5f3fc" strokeWidth="2" strokeLinecap="round" />
      </g>
    </svg>
    <div class="ssh-home-scene-caption">SMART HOME <span aria-hidden="true">·</span> LOCAL CONTROL</div>
  </div>;
}
