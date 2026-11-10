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

LoanCraft only records gold that actually changed hands. It can't make anyone repay, so use it only with players you trust and for roleplay purposes.

## Install
Copy the `LoanCraft` folder into `World of Warcraft/_forever_/Interface/AddOns/`, then click the gold coin button on your minimap in game.

## Getting around
Everything is in the UI. There are no chat commands.
- **Minimap coin:** click to open LoanCraft, shift-click for a new loan, right-click for a menu (New loan, Review transfers, Ledger, People, Options). Drag it to move it around the minimap.
- **Main window:** New loan and Options buttons. Each loan has a **...** menu to record a payment, lend more, remind, extend, forgive or delete.
- **Trade window and mailbox:** the LoanCraft panel next to them has the Pay / Lend buttons.

## Development
See [DEVELOPMENT.md](DEVELOPMENT.md) for how to run the tests and load your local copy in game, on Windows and macOS.

## Releasing to CurseForge
1. Create the project on CurseForge (game: World of Warcraft) and note its **Project ID**.
2. Create an API token at https://legacy.curseforge.com/account/api-tokens.
3. In this repo: **Settings → Secrets and variables → Actions**
   - Secret `CF_API_TOKEN` = the token
   - Variable `CURSEFORGE_PROJECT_ID` = the project ID
   - Optional for Wago Addons: secret `WAGO_API_TOKEN` and variable `WAGO_PROJECT_ID`
4. Add a `## x.y.z` section for the next version to `CHANGELOG.md` and push.
5. **Actions → Release to CurseForge → Run workflow**, then pick the bump: **patch** (1.1.0 → 1.1.1), **minor** (→ 1.2.0) or **major** (→ 2.0.0).
   - The version counts up from the last release tag. The very first release uses the top `## x.y.z` heading in `CHANGELOG.md`.
   - Tick **Beta** for `x.y.z-betaN`. N counts up on its own.
   - Tick **Dry run** to only test and build the zip, which you can download from the run. It also shows which version a real run would get. Dry runs work from any branch; real releases only from `main`.

The workflow ([.github/workflows/release.yml](.github/workflows/release.yml)) works out the version ([.github/next-version.sh](.github/next-version.sh)), checks that the changelog has a section for it, runs the tests, tags the commit, and builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager). It stamps the version into the TOC, uploads to CurseForge under the Forever flavor (from `## Interface: 16001`), and creates a GitHub release.

## License
[MIT](LICENSE)
