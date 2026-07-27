local ui = {}

function ui.colour(value)
  if term.isColor() then term.setTextColor(value) end
end

function ui.reset()
  if term.isColor() then
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
  end
end

function ui.banner(title, subtitle)
  ui.reset()
  term.clear()
  term.setCursorPos(1, 1)
  ui.colour(colors.yellow)
  print("  ____                      _   ___  ____")
  print(" / __ \ _   _  __ _ _ __ _ __| | / _ \\ / ___|")
  print("| |  | | | | |/ _` | '__| '__| | | | |\\___ \\")
  print("| |__| | |_| | (_| | |  | |  | | |_| | ___) |")
  print(" \\___\\_\\__,_|\\__,_|_|  |_| |_|  \\___/ |____/")
  ui.colour(colors.lightGray)
  print(" " .. title .. " - " .. subtitle)
  print("")
  ui.reset()
end

function ui.prompt(path)
  ui.colour(colors.yellow)
  write("quarry")
  ui.colour(colors.lightGray)
  write(":" .. path)
  ui.colour(colors.white)
  write(" $ ")
end

return ui
