# Parmesan user manual

Parmesan is a native macOS app that shows what's taking up space on your disk. This manual covers everything you can do in the app. For build and install instructions, see the [README](README.md).

## Contents

- [Scanning](#scanning)
- [The main window](#the-main-window)
- [The chart](#the-chart)
- [Color modes](#color-modes)
- [The table](#the-table)
- [Actions](#actions)
- [Settings](#settings)
- [Full Disk Access](#full-disk-access)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Where data lives](#where-data-lives)

## Scanning

### Choosing a location

A new window shows a drop zone and quick picks:

- **Volumes**: every mounted volume, with a bar showing how full it is.
- **Places**: Home, Downloads, Library and Developer (`~/Library/Developer`, where Xcode keeps its caches).
- **Recent**: folders you've scanned before. Right-click one to remove it.

You can also click **Choose Folder…**, or use **File → Scan Folder…** (⌘O when nothing is selected). **File → Scan Recent** lists recent scans too.

### Drag and drop

Drop a folder on the window to scan it (replacing what that window shows), or on Parmesan's Dock icon: an empty window takes it, otherwise it opens in a new window.

### Multiple windows

Each window scans one folder. **File → New Window** (⌘N) opens another; windows can be merged into tabs with **Window → Merge All Windows**. Scanning from the menu while the current window already shows a scan opens a new window.

### While a scan runs

Results appear right away and fill in as the scan goes: the chart and table refresh up to four times a second, and folders that haven't been fully read yet pulse gently in the chart and show an hourglass in the table. The status bar shows the items and bytes counted so far, the elapsed time and the folder being read. When scanning a whole volume, the Dock icon shows a progress bar; otherwise it shows the item count. If a scan takes more than 30 seconds and Parmesan is in the background when it finishes, you get a notification.

### Stopping

Click **Stop** in the status bar, or **Scan → Stop Scan** (⌘.). Everything read so far stays; unfinished folders keep their hourglass and are marked in the chart.

### Rescanning

- **Scan → Rescan Focus** (⇧⌘R) rescans only the folder you're looking at and splices the result into the tree.
- **Scan → Rescan All** (⌥⌘R) rescans the whole root and returns you to the same folder.

### Restricted folders

Folders Parmesan isn't allowed to read show as **Restricted**: gray hatching in the chart, a lock in the table. Their size isn't known, so it's not in the totals. The status bar shows how many there are (⚠ *N restricted*); click it to list them, reveal them in Finder, or open the Full Disk Access settings. See [Full Disk Access](#full-disk-access).

### What gets counted

- **Size** is the space allocated on disk, like `du`, unless you switch to logical size in [Settings](#settings).
- **Hard links** are counted once; the other links show a link badge and count as zero.
- **Symlinks** are never followed; they count as the link itself.
- **Packages** (`.app`, `.photoslibrary`, `.bundle`, …) count as folders, show a package badge, and can be drilled into.
- **iCloud files** that aren't downloaded take almost no space and show a cloud badge.
- **Other volumes** mounted inside the folder aren't entered (they show a drive badge) unless you turn that on in Settings. Scanning `/` counts the System and Data volumes once each.
- **APFS clones and snapshots** share blocks between files, so totals can be larger than the space actually used.

## The main window

- **Toolbar**: Back and Forward, Up to Parent, the **breadcrumb** (click any segment to jump to that folder; long paths collapse into a **…** menu), the **Sunburst / Treemap** switch, the **Color** menu, the **legend** (ⓘ), **Reveal in Finder**, **Open in Terminal**, **Largest Files**, and the **Filter** field.
- **Chart and table** side by side. Drag the divider to resize. **View → Layout** switches to stacked (chart above the table) or the table alone.
- **Status bar**: scan progress, then the totals, the time it took, the free space on the volume, and restricted folders.

The folder you're looking at is the **focus**. The chart and table always show the focus; the breadcrumb shows where it is.

## The chart

### Sunburst

The default. The center disc is the focus folder, with its name and size. The first ring holds its children, the next ring their children, and so on, 4 rings deep by default (**View → Sunburst Rings**, 2–8). Each arc's angle is proportional to its size. Arcs too thin to draw are merged into one light gray "N smaller items" arc per folder.

### Treemap

**View → Treemap** (⌘2). Each rectangle's area is proportional to its size, nested 3 levels deep by default (**View → Treemap Depth**, 1–6). Folders with room get a header strip with their name and size. Rectangles are shaded like cushions so you can tell neighbours apart; tiny ones are merged into "N smaller items".

### Interacting

| Do this | What happens |
|---|---|
| Hover | Highlights the segment and the folders it's in, and shows its name, size, % of the focus, % of the whole scan and item count |
| Click | Selects it; the table selects the matching row (or the row the item is in) and scrolls to it |
| ⌘-click or ⇧-click | Adds to or removes from the selection |
| Double-click a folder | Drills in, with a short zoom (off when Reduce Motion is on, or in Settings → Appearance) |
| Double-click a file | Opens it with its default app |
| Double-click "smaller items" | Drills into the folder they belong to |
| Click the center disc | Goes up to the parent folder |
| Click empty space | Clears the selection |
| Right-click | The [actions](#actions) menu for that item (or the whole selection, if it's part of it) |

**Show labels on the chart** in Settings → Appearance turns the names on segments on or off.

## Color modes

Pick one from the toolbar's **Color** menu or **View → Color**. The legend (ⓘ) explains the current one.

- **By Size** (default): each item's share of the folder it's in, on a warm aged-cheese scale: pale cream for small shares, straw and gold in the middle, deep amber to rind brown for the biggest.
- **By Kind**: what kind of file takes the space: Folders, Apps & Packages, Images, Video, Audio, Documents, Archives & Disk Images, Code & Dev Artifacts (`node_modules`, `DerivedData`, `.git`, source files, …), System & Library, and Other. The palette is colorblind-safe. A folder takes the color of whatever fills it most. With **Differentiate Without Color** on (System Settings → Accessibility → Display), segments also get short tags like IMG and VID.
- **By Age**: when items were last modified: cool blue for recent, warm from about a year, deep red for three years or more. A folder shows the size-weighted age of its contents, so stale data stands out.

In every mode, folders that show their contents around them are slightly muted so the leaves stand out, restricted folders are gray hatching, and "smaller items" groups are light gray. Labels switch between dark and light text to stay readable on each color.

## The table

The table lists the focus folder's direct children.

| Column | Shows |
|---|---|
| Name | Finder icon, name, and badges: package, symlink, cloud, restricted, hard link, other volume, still scanning |
| Size | Human-readable size; hover for the exact byte count |
| % | A bar in the item's chart color and its share of the focus |
| Items | Everything inside a folder, counted recursively |
| Kind | The kind Finder would show |
| Modified | Last modification date |
| Path | Only in the largest-files view |

- **Sorting**: it opens sorted by size, largest first. Click any column header to sort by it; each window remembers its sort.
- **Selection** is shared with the chart, both ways. Select several rows with ⌘-click or ⇧-click to act on them together.
- **Double-click or Return** drills into a folder or opens a file. **Space** shows Quick Look. **⌫** goes up to the parent.
- **Filter** (⌘F): type part of a name, or a pattern like `*.dmg` or `IMG_*.HEIC`. Filtering is case-insensitive.
- **Largest Files** (⌘L, or the toolbar's list button): lists the 500 largest files anywhere below the focus, with their paths. This is the "what are the biggest files on my disk" view.

## Actions

From the **Item** menu, the right-click menu on the chart and table, and the toolbar. They act on the selection, or on the focus folder when nothing is selected.

| Action | Shortcut | What it does |
|---|---|---|
| Reveal in Finder | ⌘R | Opens Finder with the items selected |
| Open in Terminal | ⌥⌘T | Opens the folder (a file's parent folder) in your terminal; pick which one in Settings → General |
| Open | ⌘O (with a selection) | Opens the items with their default apps |
| Quick Look | Space, ⌘Y | Previews the items; press again to close |
| Get Info | ⌘I | Opens Finder's Info window. The first time, macOS asks whether Parmesan may control Finder |
| Copy Path | ⌥⌘C | Copies the POSIX paths, one per line |
| Copy Size Summary | ⇧⌘C | Copies "name — size" lines |
| Move to Trash | ⌘⌫ | Moves the items to the Trash after a confirmation showing the space freed. The totals update right away, without a rescan. Nothing is ever deleted: put items back from the Trash in Finder |
| Drill In | ⌘↓ | Into the selected folder |

Items under `/System`, `/usr`, `/bin`, `/sbin`, `/Library/Apple`, or protected by System Integrity Protection always ask first, with a warning, and the **Move to Trash** button only works while you hold ⌥. You can't trash the folder you scanned from inside its own window.

## Settings

Open with **Parmesan → Settings…** (⌘,).

### General

- **Terminal**: which app Open in Terminal uses: Terminal, iTerm, Ghostty, Warp, WezTerm or kitty (only installed ones are listed; if the one you chose is uninstalled, Terminal is used).
- **Confirm before moving to the Trash** (on by default). Items in system locations always ask.
- **Restore last scan on launch**: rescans the most recent folder when Parmesan opens without windows to restore.

### Scanning

- **Size**: allocated size on disk (default) or logical size. Applies right away.
- **Cross into other volumes** (off): enter other volumes mounted inside the scanned folder.
- **Count hard links once** (on).
- **Include hidden files** (on): dot-files and items flagged hidden.
- **Skip Paths**: one glob pattern per line. Patterns with a `/` match full paths (`~` is your Home folder), others match names. For example `node_modules`, `*.photoslibrary`, `~/Library/Caches/*`. Lines starting with `#` are ignored.

Changes apply to the next scan (except Size).

### Appearance

- **Appearance**: System, Light or Dark.
- **Default chart**, **Sunburst rings**, **Treemap levels** and **Color**: what new windows start with. Each window can change them from the View menu.
- **Show labels on the chart**.
- **Animate drilling in and out** (also off when Reduce Motion is on).

## Full Disk Access

macOS keeps some folders private: Mail, Messages, Safari, other apps' containers, Time Machine, and parts of `~/Library`. Without Full Disk Access, Parmesan can't see inside them, so they're Restricted and their size isn't counted.

On first launch without it, Parmesan explains this and offers to open **System Settings → Privacy & Security → Full Disk Access**. Turn Parmesan on there (or click **+** and choose the app), then rescan. You can get back to it from **Help → Grant Full Disk Access…** or the restricted-folders list in the status bar. Parmesan works without it; it just can't count those folders.

If you build Parmesan yourself, each rebuild needs the permission granted again, unless you sign with a stable identity. See the [README](README.md#full-disk-access).

## Keyboard shortcuts

**Help → Keyboard Shortcuts** (⌘/) shows these in a window.

| Action | Shortcut |
|---|---|
| Scan Folder (nothing selected) | ⌘O |
| New Window | ⌘N |
| Rescan Focus | ⇧⌘R |
| Rescan All | ⌥⌘R |
| Stop Scan | ⌘. |
| Reveal in Finder | ⌘R |
| Open in Terminal | ⌥⌘T |
| Open (selection) | ⌘O |
| Quick Look | Space, ⌘Y |
| Get Info | ⌘I |
| Copy Path | ⌥⌘C |
| Copy Size Summary | ⇧⌘C |
| Move to Trash | ⌘⌫ |
| Drill In | ⌘↓, Return, double-click |
| Up to Parent | ⌘↑, ⌫ |
| Back / Forward | ⌘[ / ⌘] |
| Go to Root | ⇧⌘↑ |
| Sunburst / Treemap | ⌘1 / ⌘2 |
| Show Largest Files | ⌘L |
| Filter | ⌘F |
| Keyboard Shortcuts | ⌘/ |
| Settings | ⌘, |

Every shortcut is in the menus, so **Help** search finds them.

## Where data lives

- **Settings and recent scans**: `UserDefaults` under the app ID `com.breadthe.Parmesan`. Recent scans are stored as bookmarks, so they follow folders you move.
- **Scan results** live only in memory while a window is open. Nothing is written to disk.
- **Nothing leaves your Mac.** Parmesan makes no network requests at all.
