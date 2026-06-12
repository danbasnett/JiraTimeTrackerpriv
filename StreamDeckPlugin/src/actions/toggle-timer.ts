import streamDeck, {
  action,
  KeyDownEvent,
  SingletonAction,
} from "@elgato/streamdeck";
import { exec } from "child_process";

@action({ UUID: "com.danbasnett.jiratimetracker.toggle" })
export class ToggleTimer extends SingletonAction {
  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    exec('open "jiratimetracker://toggle"', (error) => {
      if (error) {
        streamDeck.logger.error(`Failed to send toggle command: ${error.message}`);
      }
    });
  }
}
