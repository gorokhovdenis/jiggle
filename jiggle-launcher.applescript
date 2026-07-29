-- Jiggle: открывает новое окно iTerm и запускает джигглер.
--
-- Настройки правятся в строке settings ниже, после чего пересобрать:
--   ./build-jiggle-app.sh
--
-- Сам jiggle.sh лежит внутри бандла (Contents/Resources), путь к нему
-- вычисляется от расположения приложения. Поэтому приложение не зависит от
-- того, куда распакованы исходники, и переживает их перемещение и удаление.

on run
	set settings to "JIGGLE_MIN=5 JIGGLE_MAX=10 JIGGLE_DELTA=400 JIGGLE_EASE=500"
	set scriptPath to (POSIX path of (path to me)) & "Contents/Resources/jiggle.sh"
	set theCommand to settings & " " & quoted form of scriptPath

	tell application "iTerm"
		activate
		set newWindow to (create window with default profile)
		tell current session of newWindow
			write text theCommand
		end tell
	end tell
end run
