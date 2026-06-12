import streamDeck from "@elgato/streamdeck";
import { ToggleTimer } from "./actions/toggle-timer";
import { PauseResume } from "./actions/pause-resume";
import { StopAndLog } from "./actions/stop-and-log";

// Register actions
streamDeck.actions.registerAction(new ToggleTimer());
streamDeck.actions.registerAction(new PauseResume());
streamDeck.actions.registerAction(new StopAndLog());

// Connect to Stream Deck
streamDeck.connect();
