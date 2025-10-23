# Getting Started with Your Coder Workspace

> Think of this like setting up a gaming console - you need the console (Coder server), the game (this template), and a controller (your Windows PC) to play.

## What Is This?

This template creates a *cloud computer* that lives on Kubernetes. You connect to it from your Windows PC and write code there instead of on your local machine.

*Why?* Your workspace has everything already installed (Java, Node.js, Python, Docker) and runs on powerful servers, not your laptop.

---

## Part 1: What You Need on Your Windows PC

### Must Have
1. *Coder CLI* - The remote control for your cloud workspace
   - Download from your company's Coder URL at `/bin` (like `https://coder.yourcompany.com/bin`)
   - Or grab it from GitHub Releases
   - Add it to your PATH so you can type `coder` in any terminal

### Pick Your Coding Tool
Choose ONE (or use all three!):

1. *Web Browser* (easiest)
   - Chrome, Edge, or Firefox
   - No installation needed
   - Click buttons in Coder to open VS Code or JupyterLab

2. *VS Code* (most popular)
   - Install VS Code
   - Add the Coder Remote Extension
   - Connect via the extension

3. *JetBrains Toolbox* (for Java/Python pros)
   - Install JetBrains Toolbox
   - Use Toolbox to install IntelliJ or PyCharm
   - Toolbox can connect directly to Coder workspaces
---

## Part 2: First Time Setup

### Step 1: Log In to Coder
Open a terminal (PowerShell or Command Prompt) and type:

coder login https://coder.yourcompany.com

It will open your browser to log in. Once done, your terminal is connected.

### Step 2: Create Your Workspace
1. Go to your Coder dashboard in a web browser
2. Click *"Create Workspace"*
3. Select this template (it might be called "Universal Docker" or similar)
4. Pick your resources:
   - *CPU*: How fast your workspace runs (4 cores is good)
   - *Memory*: How much RAM (8 GB is good)
   - *Disk*: How much storage (50 GB is good)
5. Click *"Create"*

Wait 2-3 minutes while Coder builds your workspace.

### Step 3: Connect to Your Workspace

#### Option A: Use Your Browser (easiest)
1. In the Coder dashboard, click on your workspace
2. Click the *"VS Code Web"* or *"JupyterLab"* button
3. Start coding!

#### Option B: Use VS Code on Windows
1. Open VS Code
2. Press `Ctrl+Shift+P` to open the command palette
3. Type "Coder" and select *"Connect to Workspace"*
4. Pick your workspace from the list
5. VS Code will connect and open a remote window

#### Option C: Use JetBrains Toolbox
1. Open JetBrains Toolbox
2. Select your IDE (IntelliJ or PyCharm)
3. Look for the Coder integration
4. Connect to your workspace

#### Option D: Use SSH (terminal)
1. Run: `coder config-ssh`
2. This adds your workspace to your SSH config
3. Now you can SSH in: `ssh coder.your-workspace-name`

---

## Part 3: What's Already Installed in Your Workspace?

Your cloud computer comes with:
- *Docker* - Run containers inside your workspace
- *Java 17* - With Maven and Gradle
- *Node.js* (latest LTS) - With pnpm and Angular CLI
- *Python* - With FastAPI and database drivers
- *VS Code Web* - Browser-based coding
- *JupyterLab* - For data science notebooks
- *JetBrains support* - For IntelliJ and PyCharm

Everything auto-installs the first time your workspace starts (takes ~5 minutes).

---

## Part 4: Daily Workflow

### Starting Your Day
1. Go to Coder dashboard
2. Click *"Start"* on your workspace (if it's stopped)
3. Wait 30 seconds for it to wake up
4. Connect using your preferred method (browser/VS Code/JetBrains)

### Ending Your Day
- Your workspace auto-stops after inactivity (saves resources)
- Or manually click *"Stop"* in the dashboard
- Don't worry - all your files are saved automatically

---

## Part 5: Common Questions

*Q: Where are my files?*
A: Everything in `/home/coder` is saved permanently. Even if you delete and recreate your workspace, your files stick around.

*Q: Can I use Docker?*
A: Yes! Just type `docker` commands like normal. Docker-in-Docker is enabled.

*Q: What if I need a different Node.js version?*
A: The workspace uses `nvm`. Just run `nvm install 18` (or any version) and `nvm use 18`.

*Q: What if I need more disk space?*
A: Stop your workspace, edit it in Coder, increase the disk size, then restart.

*Q: Can I install more stuff?*
A: Yes! You have `sudo` access. Install anything with `sudo apt-get install`.

*Q: My workspace feels slow. What do?*
A: Stop it, edit the resources (increase CPU/RAM), then restart.

---

## Part 6: Pro Tips

1. *Use Git* - Clone your repos into `/home/coder/project`
2. *Browser coding* - No installation needed, works from any computer
3. *SSH tricks* - After `coder config-ssh`, you can `scp` files or use any SSH tool
4. *Port forwarding* - Run a web app on port 3000? Coder auto-forwards it to your browser
5. *Disk cleanup* - The workspace auto-cleans Docker images when disk is >80% full

---

## Troubleshooting

*Workspace won't start?*
- Check the Coder dashboard for error messages
- Try deleting and recreating the workspace

*Can't connect from VS Code?*
- Make sure you ran `coder login` first
- Check the Coder extension is installed
- Restart VS Code

*SSH not working?*
- Run `coder config-ssh` again
- Make sure the workspace is running
- Try `ssh coder.workspace-name` exactly as shown in the dashboard

*Need help?*
- Ask in your team's Slack/chat
- Check Coder docs at your company's Coder URL

---

## Summary (TLDR)

1. Install Coder CLI on Windows
2. Run `coder login https://your-coder-url.com`
3. Create workspace from template
4. Connect via browser, VS Code, or JetBrains
5. Code in the cloud, not on your laptop
6. Everything (Java, Node, Python, Docker) is pre-installed
7. Your files in `/home/coder` are saved forever

That's it! You now have a powerful cloud development environment. 🚀

