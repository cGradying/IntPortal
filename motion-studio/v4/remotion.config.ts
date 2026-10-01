import { Config } from "@remotion/cli/config";

// Rendering uses the Chrome Headless Shell that HyperFrames installed, so
// both engines rasterize with the same browser build.
Config.setBrowserExecutable("/root/.cache/hyperframes/chrome/chrome-headless-shell/linux-152.0.7977.30/chrome-headless-shell-linux64/chrome-headless-shell");
Config.setVideoImageFormat("png");
Config.setCodec("h264");
Config.setCrf(16);
Config.setPixelFormat("yuv420p");
Config.setConcurrency(4);
Config.setChromiumOpenGlRenderer("swangle");
