# Free to try and the V-Key

Esper is free to try; one in-app purchase, the **V-Key**, opens the whole game. Code: `ProjectEsper/Store/VKey.swift` (rules, `VKey`; store, `VKeyStore`), the screen `ProjectEsper/View/VKeyScreen.swift`.

## Free to try
- **Modes:** Rounds only. 47, ZONES and Breaker Ball open the V-Key screen.
- **Stages:** the Wreck Center only. The rest show red with `pixel_lock` in the box's upper right; they can still be highlighted and previewed, and picking one opens the V-Key screen.
- **Colours:** Topaz (orange) and Larimar (teal). Every colour can be tried on in the customize screen, but START/READY with a locked one opens the V-Key screen. No lock icons there, by choice.
- **Outfits:** all free, in either free colour.
- **Greateraid:** never locked. Locking some drinks but not others would say the locked ones are better.
- **The Tutorial:** free.

## Online
- Without the key on either side, the match is Rounds on the Wreck Center, whatever the host asked for.
- The colour clash: a side with the key keeps its colour; a side without gives way to the other free colour. Two keyed sides clash as before, the second giving way to the opposite.
- Each phone's key goes in its hello (protocol 230), fixed for the match, so a purchase partway can't make the phones disagree.

## Builds
- Debug: unlocked. The title's debug V-KEY switch takes the key away to see the locks.
- TestFlight and the App Store: the real purchase; TestFlight's is the sandbox's.
- Product: `com.sorsec0de.projectesper.vkey`, non-consumable, in App Store Connect.

## Backers
Diamond was already a $5+ pledge reward. Every $5+ tier gets a V-Key, which brings Diamond with it.
