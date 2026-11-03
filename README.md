# Journal (iOS) — try it online

This folder builds the Journal app for the iPhone simulator on a free GitHub Mac,
then you run it in your browser with Appetize.io. No Mac needed.

## 1. Put it on GitHub (about 3 minutes, all in the browser)
1. Sign in at github.com and create a **new repository** called `journal-ios` (Private is fine).
2. On the empty repo page, choose **uploading an existing file**.
3. Drag in everything from this folder: `project.yml`, `README.md`, the `Sources` folder
   and the `.github` folder. Click **Commit changes**.
   - If the `.github` folder doesn't upload: choose **Add file → Create new file**, type the
     name `.github/workflows/build.yml`, paste in the contents of that file, and commit.

## 2. Let GitHub build it (about 5–10 minutes)
1. Open the **Actions** tab. A run called **Build simulator app** starts by itself.
   (If not, click it, then **Run workflow**.)
2. When it shows a green tick, open the run and download **Journal-simulator** under *Artifacts*.
3. GitHub gives you a zip that contains `Journal-simulator.zip`. Unzip the outer one only.

If the run shows a red cross, open the failed step and copy the lines starting with `error:`.
Send those to Claude to fix.

## 3. Run it online
1. Go to appetize.io/upload and upload `Journal-simulator.zip`.
2. Pick an iPhone and tap play. The app opens on its setup screen.

Notes: in the simulator, location can be set from Appetize's device settings, or search for
your suburb instead. Live weather, markets and news need the internet, which Appetize provides.
