import streamDeck, {
  action,
  KeyDownEvent,
  SingletonAction,
} from "@elgato/streamdeck";
import { exec } from "child_process";

@action({ UUID: "com.danbasnett.jiratimetracker.pause-resume" })
export class PauseResume extends SingletonAction {
  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    // The app handles the toggle logic — if running it pauses, if paused it resumes
    exec('open "jiratimetracker://toggle"', (error) => {
      if (error) {
        streamDeck.logger.error(`Failed to send pause/resume command: ${error.message}`);
      }
    });
  }
}
