/**
 * Avalon anti-cheat — server-side vote/quest tally.
 * Copy to functions/index.js and `firebase deploy --only functions`.
 *
 * Hides the raw approve/reject and success/fail values from players while a round is open.
 * While votes arrive it publishes only the LIST OF WHO HAS VOTED (no values). When everyone has
 * voted it writes the aggregate result and deletes the raw votes.
 *
 * The host's browser still drives phase transitions; it reads `voteProgress` / `missionProgress`
 * (safe) instead of the raw `teamVotes` / `missionVotes` (which the rules hide).
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.database();

// ── Team vote: tally approve/reject once every player has voted ──
exports.tallyTeamVotes = functions.database
  .ref('/rooms/{code}/teamVotes/{uid}')
  .onWrite(async (change, ctx) => {
    const { code } = ctx.params;
    const roomRef = db.ref(`/rooms/${code}`);
    const roomSnap = await roomRef.get();
    const room = roomSnap.val();
    if (!room || room.phase !== 'vote-team') return null;

    const votes = room.teamVotes || {};
    const voters = Object.keys(votes);
    const playerCount = Object.keys(room.players || {}).length;

    // Always publish WHO has voted (ids only) so the host can bot-fill the missing seats.
    await roomRef.child('voteProgress').set({ voted: voters, total: playerCount });

    if (voters.length < playerCount) return null;       // not everyone yet

    let approve = 0, reject = 0;
    voters.forEach((id) => { votes[id] === 'approve' ? approve++ : reject++; });
    const passed = approve > reject;                    // tie = reject

    await roomRef.update({
      phase: 'vote-result',
      voteResult: { approve, reject, passed },
      teamVotes: null,                                  // wipe the raw votes
      voteProgress: null,
    });
    return null;
  });

// ── Quest cards: tally success/fail once every team member has played ──
exports.tallyMissionVotes = functions.database
  .ref('/rooms/{code}/missionVotes/{uid}')
  .onWrite(async (change, ctx) => {
    const { code } = ctx.params;
    const roomRef = db.ref(`/rooms/${code}`);
    const roomSnap = await roomRef.get();
    const room = roomSnap.val();
    if (!room || room.phase !== 'mission') return null;

    const team = room.currentTeam || [];
    const votes = room.missionVotes || {};
    const played = Object.keys(votes);

    await roomRef.child('missionProgress').set({ played, total: team.length });

    if (played.length < team.length) return null;

    let successes = 0, fails = 0;
    played.forEach((id) => { votes[id] === 'success' ? successes++ : fails++; });

    // Two fails required on quest 4 for 7+ players (standard Avalon).
    const mn = room.currentMission || 1;
    const need = (mn === 4 && (room.playerCount || 0) >= 7) ? 2 : 1;
    const passed = fails < need;

    // Hand back the result and start the 5s reveal countdown; the host reveals it.
    await roomRef.update({
      phase: 'mission-reveal',
      revealAt: admin.database.ServerValue.TIMESTAMP, // host adds the 5s window client-side
      pendingMissionResult: { successes, fails, passed, missionNum: mn },
      missionVotes: null,
      missionProgress: null,
    });
    return null;
  });
