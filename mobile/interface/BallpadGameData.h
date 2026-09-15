// Ballpad's game-data store and importer, as the rest of the app sees it.
//
// The port calls the two hooks in port/hostui.h; the overlay's "Game Data & Saves" rows call the
// functions here. Both doors reach the same store and the same import flow, so "imported" cannot
// mean two different things depending on how the player got there. See BallpadGameData.mm for the
// store layout, and docs/36-native-strikers-progress.md ("N5 — Ballpad's Files importer") for the
// design of record.

#ifndef BALLPAD_GAME_DATA_H
#define BALLPAD_GAME_DATA_H

#ifdef __cplusplus
extern "C" {
#endif

// Whether the store currently names game data, and that data is still there: reads the activation
// record and stats what it names. No UI and no Foundation object, because the port asks this kind
// of question from a static initialiser (this is what PortHostUIGameDataPath answers with).
int BallpadGameDataStaged(void);

// Where the store lives, for the diagnostic report and the log. Never NULL.
const char* BallpadGameDataStorePath(void);

// One line describing what the store holds -- the staged file's name and size, or "no game data" --
// for a log line or an alert's subtitle. Never NULL.
const char* BallpadGameDataSummary(void);

// Opens the Files document picker over the running game and stages what the player picks. Answers
// from the picker's own delegate, so this returns as soon as the picker is up rather than when the
// player has chosen: the game keeps running behind it, and an import from here takes effect on the
// next launch, which is what the completion alert says.
void BallpadGameDataPresentImport(void);

// The other half of the same flow, for the player who has already put an image in the app's own
// Documents folder through Files rather than picking one out of Browse. Lists what is there and
// stages whichever one is chosen, through the same validation and the same store.
void BallpadGameDataPresentFolderImport(void);

// Removes everything in the store, after the overlay has already asked the player to confirm.
// Returns the number of files removed, so the caller can tell "removed" from "there was nothing".
int BallpadGameDataRemoveStoredData(void);

#ifdef __cplusplus
}
#endif

#endif // BALLPAD_GAME_DATA_H
