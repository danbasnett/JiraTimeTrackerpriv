import streamDeck, {
  action,
  KeyDownEvent,
  SingletonAction,
} from "@elgato/streamdeck";
import { exec } from "child_process";

@action({ UUID: "com.danbasnett.jiratimetracker.stop" })
export class StopAndLog extends SingletonAction {
  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    exec('open "jiratimetracker://stop"', (error) => {
      if (error) {
        streamDeck.logger.error(`Failed to send stop command: ${error.message}`);
      }
    });
  }
}
