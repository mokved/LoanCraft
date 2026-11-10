# Running LoanCraft locally

There are two ways to check a change: the automated tests, which need no game, and loading your copy of the addon in World of Warcraft: Forever.

## 1. Get the code

```
git clone https://github.com/asenrusev/LoanCraft.git
cd LoanCraft
```

The addon files sit at the repo root. `LoanCraft.toc` lists them in load order.

## 2. Run the automated tests

The tests run several simulated players who trade, mail and sync with each other, inside a Lua 5.1 runtime. You need **Python 3.9 or newer**.

Set up once (a virtual environment keeps `lupa` out of your system Python):

**macOS / Linux**
```
python3 -m venv .venv
source .venv/bin/activate
pip install lupa
```

**Windows (PowerShell)**
```
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install lupa
```
If PowerShell refuses to run the activate script, run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, or use `cmd` and `.venv\Scripts\activate.bat` instead.

Then, every time (with the virtual environment activated):
```
python tests/test_addon.py
```

Each check prints `PASS` or `FAIL`, and the run ends with `FAILURES: 0` when everything works. The process exits with a non-zero code if anything fails.

## 3. Load it in the game

### Find your AddOns folder
In the Battle.net app, select the game, click the ⚙ next to **Play**, and choose **Show in Explorer** (Windows) or **Show in Finder** (macOS). Inside, go to `_forever_/Interface/AddOns`. Create the `Interface` and `AddOns` folders if they don't exist yet.

Default locations:
- **Windows:** `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`
- **macOS:** `/Applications/World of Warcraft/_forever_/Interface/AddOns`

### Link your copy into it (recommended)
A link makes the game load straight from your repo, so you never have to copy files again. The link **must be named `LoanCraft`** to match the `.toc` file. Your clone's folder can have any name.

**Windows** (in `cmd`, from the repo folder; a junction doesn't need admin rights):
```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\LoanCraft" "%CD%"
```
Or in PowerShell:
```
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\LoanCraft" -Target (Get-Location)
```

**macOS / Linux** (from the repo folder):
```
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/LoanCraft"
```

Adjust the path if your game is installed somewhere else. To remove the link later, delete the `LoanCraft` link in the AddOns folder; your repo is not affected.

**Simplest alternative:** copy the repo folder into `AddOns` and rename it to `LoanCraft`. You will have to copy it again after every change.

### Try your change
1. Start the game. At character select, click **AddOns** and make sure **LoanCraft** is enabled.
2. Log in and click the gold coin button on the minimap.
3. Turn on Lua error popups once: `/console scriptErrors 1`. The BugSack addon is a nicer alternative.
4. After editing a `.lua` file, type `/reload` in game to load the change.
5. After adding, removing or renaming a file in `LoanCraft.toc`, fully restart the game. `/reload` does not pick up TOC changes.

Notes:
- The version shows as `@project-version@` when you run from source. The real number is only filled in when a release is built.
- Trades, mail and sync need a second player. Use a second account or a friend, or rely on the automated tests, which cover these flows.
- Don't keep an installed release of LoanCraft (or an older copy under another folder name) enabled next to your local copy.

### Start with clean data
LoanCraft saves its data in:
```
_forever_/WTF/Account/<ACCOUNT NAME>/SavedVariables/LoanCraft.lua
```
To start fresh, **exit the game first** and then delete or rename that file. The game rewrites it when you log out, so changes made while it is running are lost.

## Before opening a pull request
- `python tests/test_addon.py` ends with `FAILURES: 0`.
- You tried the change in game and got no Lua errors.
- If players will notice the change, add a line to `CHANGELOG.md`.
