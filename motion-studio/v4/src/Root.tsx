import { Composition } from "remotion";
import { Film } from "./Film";
import { FPS, FRAMES } from "./lib/motion";

export const Root = () => (
  <Composition id="Main" component={Film} durationInFrames={FRAMES} fps={FPS} width={1920} height={1080} />
);
