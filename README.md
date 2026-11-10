# LoanCraft

A World of Warcraft: Forever addon for gold loans between players. Lend by trade or mail, set interest and due dates, and let LoanCraft keep the books: it notices repayments, reminds people, and shows what you've earned in interest.

> ⚠️ **Important: LoanCraft cannot make anyone pay you back.** It only keeps records. It can't take gold, lock items or enforce a loan in any way. Once you hand gold over, getting it back depends entirely on the other player. **Use LoanCraft only with players you trust, and for roleplay purposes.** Never lend gold you can't afford to lose.

## Features
- **Trade or mail gold, and LoanCraft asks what it was:** a new loan, a repayment, lending more, or nothing to do with loans. If both players run LoanCraft, one answer settles it for both.
- **Pay / Lend buttons** next to the trade window and mailbox fill in the exact gold.
- **Player picker:** type-ahead suggestions from target, loan partners, recent contacts, group, friends and guild. Shift-click names in chat.
- **Gold, silver and copper** in separate boxes.
- **Interest, due dates and late fees.** Remembers the terms you last used per player.
- **Ledger** with interest split out, a profit/loss summary and CSV export.
- **People** tab with reliability ratings.
- **Minimap button** that glows red (overdue), orange (due within a day) or blue (needs your decision).
- **Tooltips and reminders:** player tooltips show debts, and you get reminders at login, before due dates and when overdue.
- **Sync** with the other player's LoanCraft. The lender stays in charge of the record, so nobody can erase their own debt.

## Install
Copy the `LoanCraft` folder into `World of Warcraft/_forever_/Interface/AddOns/`, then click the gold coin button on your minimap in game.

## Getting around
Everything is in the UI. There are no chat commands.
- **Minimap coin:** click to open LoanCraft, shift-click for a new loan, right-click for a menu (New loan, Review transfers, Ledger, People, Options). Drag it to move it around the minimap.
- **Main window:** New loan and Options buttons. Each loan has a **...** menu to record a payment, lend more, remind, extend, forgive or delete.

## Development
See [DEVELOPMENT.md](DEVELOPMENT.md) for how to run the tests and load your local copy in game, on Windows and macOS.

## License
[MIT](LICENSE)
