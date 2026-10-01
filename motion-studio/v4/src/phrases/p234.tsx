// Phrases 2-4: the phone. Shape stays the phone; the camera and the cursor
// carry the rhythm while the inner elements morph.
import { C, P, PH } from "../theme";
import type { Phrase } from "../types";
import { PhoneInside } from "../screens/phone";
import { knobX } from "../screens/grades";
import { LINE_W, LINE_Y } from "../screens/notes";

const W = (x: number, y: number): [number, number] => P(x, y);
const at = (b: number, [x, y]: [number, number]): [number, number, number] => [b, x, y];
const camY = (localY: number) => PH.cy - PH.h / 2 + localY; // phone-local y -> world y

// ---------------------------------------------------------------- phrase 2
export const p2: Phrase = {
  name: "p2",
  from: 28,
  to: 56,
  shape: [],
  cam: [
    [28, { cy: camY(315), z: 2.05 }],
    [32, { cy: 560, z: 1.3 }],
    [37, { cy: camY(640), z: 1.65 }],
    [42, { cy: 560, z: 1.3 }],
    [43, { cy: camY(150), z: 2.25 }],
    [48, { cy: 560, z: 1.3 }],
    [52, { cy: camY(100), z: 2.3 }],
    [54.4, { cy: 580, z: 1.22 }],
  ],
  cur: [
    at(26.4, W(250, 230)), // to the next-class card
    at(31, W(240, 560)), // to the timeline
    at(33, W(240, 500)), // drag: locked to the scroll keys
    at(34, W(240, 410)),
    at(35.2, W(238, 272)), // to the free block
    at(38.2, W(210, 432)), // to the sheet handle
    at(41, W(210, 612)), // drag the sheet down
    at(42.4, W(134, 108)), // to Tue in the week strip
    at(44, W(210, 108)), at(45, W(286, 108)), at(46, W(362, 108)), at(47, W(134, 108)),
    at(47.6, W(250, 490)), // to GEED 10053
    at(50, W(376, 100)), // to close
    at(52.4, W(300, 300)),
    at(53.6, W(162, 836)), // to the Grades tab
  ],
  clicks: [28, 36, 48, 51, 55],
  holds: [[32, 35], [40, 41.7], [43.6, 47.3]],
  events: [
    [28, "click: card -> hero"], [29, "7:30 rolls"], [30, "in 9 min"], [31, "free bar fills"],
    [32, "grab timeline"], [33, "row snaps"], [34, "row snaps"], [35, "release, momentum"],
    [36, "click free block"], [37, "sheet grows"], [38, "1h 30m free"], [39, "suggestions"],
    [40, "grab handle"], [41, "drag down"], [42, "sheet folds back"], [43, "island: next class"],
    [44, "Wed"], [45, "Thu"], [46, "Fri"], [47, "back to Tue"],
    [48, "click GEED"], [49, "detail grows"], [50, "room + map"], [51, "close"],
    [52, "Isko line-art notification"], [53, "Leave at 12:50"], [54, "folds into island"], [55, "tab -> Grades"],
  ],
  Inside: PhoneInside,
};

// ---------------------------------------------------------------- phrase 3
const SLY = 620 + 112; // slider track, phone-local y
export const p3: Phrase = {
  name: "p3",
  from: 56,
  to: 84,
  shape: [],
  cam: [
    [55.6, { cy: camY(240), z: 2.3 }],
    [60, { cy: camY(470), z: 1.75 }],
    [63.4, { cy: camY(700), z: 2.15 }],
    [70.4, { cy: 580, z: 1.22 }],
    [72, { cy: camY(380), z: 1.75 }],
    [76, { cy: camY(250), z: 2.3 }],
    [78, { cy: camY(470), z: 1.25 }], // pull back while the pill drops to the bar
    [80, { cy: camY(690), z: 1.75 }], // then push in on the typing
  ],
  cur: [
    at(62.8, W(20 + knobX(1.5), SLY)), // to the knob
    at(65, W(20 + knobX(1.4), SLY)), at(66, W(20 + knobX(1.3), SLY)), at(67, W(20 + knobX(1.25), SLY)),
    at(68, W(340, 560)),
    at(69.8, W(257, 836)), // Notes tab
    at(72, W(42, 132 + LINE_Y(0) + 12)), // start of line 1
    at(73, W(40 + LINE_W[0], 132 + LINE_Y(0) + 12)),
    at(74, W(40 + LINE_W[1], 132 + LINE_Y(1) + 12)),
    at(75, W(40 + LINE_W[2], 132 + LINE_Y(2) + 12)),
    at(75.9, W(108, 202)), // Ask Isko
    at(78.2, W(330, 690)),
    at(81.8, W(374, 771)), // send
  ],
  clicks: [71, 77, 83],
  holds: [[64, 67.5], [72.8, 75.5]],
  events: [
    [56, "GWA 2.10"], [57, "GWA 1.60"], [58, "GWA 1.28 + Dean's list"], [59, "sparkline draws"],
    [60, "row 1"], [61, "row 2"], [62, "row 3"], [63, "row 4"],
    [64, "grab knob"], [65, "goal 1.40"], [66, "goal 1.30"], [67, "goal 1.25"],
    [68, "slider -> coach"], [69, "Aim for 1.19"], [70, "subjects left"], [71, "tab -> Notes"],
    [72, "note grows"], [73, "select line 1"], [74, "select line 2"], [75, "select line 3"],
    [76, "Ask Isko pill"], [77, "click pill"], [78, "pill -> command bar"], [79, "caret"],
    [80, "type: What's a"], [81, "type: balanced"], [82, "type: BST?"], [83, "click send"],
  ],
};

// ---------------------------------------------------------------- phrase 4
export const p4: Phrase = {
  name: "p4",
  from: 84,
  to: 112,
  shape: [[111, { w: 40, h: 40, r: 20 }]],
  fill: [[111, C.ink]],
  lift: [[110.6, 0]],
  cam: [
    [83.6, { cy: camY(350), z: 1.7 }],
    [88, { cy: camY(370), z: 1.8 }],
    [92, { cy: camY(500), z: 1.4 }],
    [95.4, { cx: 1010, cy: camY(330), z: 2.2 }],
    [97.6, { cx: 960, cy: camY(260), z: 1.6 }],
    [99, { cy: camY(560), z: 1.3 }],
    [101, { cy: camY(500), z: 1.6 }],
    [104, { cy: camY(560), z: 1.3 }],
    [108.6, { cy: camY(460), z: 1.5 }],
    [111, { cx: 960, cy: 540, z: 2.6 }],
  ],
  cur: [
    at(84.2, W(340, 690)),
    at(88.2, W(370, 620)),
    at(95.1, W(323, 328)), // wifi toggle
    at(97.3, W(380, 520)),
    at(99.1, W(82, 767)), // Cards
    at(103.1, W(210, 767)), // Quiz
    at(105.1, W(214, 522)), // option B
    at(107.1, W(338, 767)), // Plan
    at(110.2, W(395, 620)),
  ],
  clicks: [96, 100, 104, 106, 108],
  events: [
    [84, "divider 1"], [85, "divider 2"], [86, "divider 3"], [87, "chunk dots"],
    [88, "meaning map scatter"], [89, "question lands"], [90, "3 nearest ring"], [91, "lines connect"],
    [92, "bar -> answer card"], [93, "answer streams"], [94, "citation 1"], [95, "citations 2-3"],
    [96, "click wifi"], [97, "toggle off"], [98, "island: offline"], [99, "on this phone"],
    [100, "click Cards"], [101, "card stack"], [102, "fan"], [103, "flip"],
    [104, "click Quiz"], [105, "options"], [106, "pick B (wrong)"], [107, "why? explanation"],
    [108, "click Plan"], [109, "plan rows 1-2"], [110, "plan row 3"], [111, "shape -> black dot"],
  ],
};
