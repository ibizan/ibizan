
moment = require 'moment'
uuid = require 'node-uuid'

{ HEADERS, REGEX } = require '../helpers/constants'
MODES = ['in', 'out', 'vacation', 'unpaid', 'sick']
Organization = require('../models/organization').get()

class Punch
  constructor: (@mode = 'none', 
                @times = [], 
                @projects = [],
                @notes = '') ->
    # ...

  @parse: (user, command, mode='none') ->
    if not user or not command
      return
    if mode and mode isnt 'none'
      [mode, command] = parseMode command

    [start, end] = user.activeHours()
    [times, command] = parseTime command, start, end
    [dates, command] = parseDate command

    datetimes = []
    if times.length > 0 and dates.length > 0
      for date in dates
        for time in times
          datetime = moment(date)
          datetime.hour(time.hour())
          datetime.minute(time.minute())
          datetime.second(time.second())
          datetimes.push datetime
    else if times.length > 0
      datetimes = times
    else if dates.length > 0
      datetimes = dates

    if times.block?
      datetimes.block = times.block

    [projects, command] = parseProjects command
    notes = command.trim()

    punch = new Punch(mode, datetimes, projects, notes)
    punch

  toRawRow: (name) ->
    headers = HEADERS.rawdata
    row = {}
    row[headers.id] = uuid.v1()
    row[headers.today] = moment().format('MM/DD/YYYY')
    row[headers.name] = name
    if @times.block?
      block = @times.block
      hours = Math.floor block
      minutes = Math.round((block - hours) * 60)
      row[headers.blockTime] = "#{hours}:#{if minutes < 10 then "0#{minutes}" else minutes}:00"
    else
      row[headers[@mode]] = @times[0].format('hh:mm:ss A')
    row[headers.notes] = @notes
    max = if @projects.length < 6 then @projects.length else 5
    for i in [0..max]
      project = @projects[i]
      if project?
        row[headers["project#{i + 1}"]] = "##{project.name}"
    row

  assignRow: (row) ->
    @row = row

  isValid: (user) ->
    # fail cases
    # if mode is 'in' and user has not punched out
    # if mode is 'in' and date is yesterday
    # if mode is 'unpaid' and user is non-salary
    # if mode is 'vacation' and user doesn't have enough vacation time
    # if mode is 'sick' and user doesn't have enough sick time
    # if mode is 'vacation' and time isn't divisible by 4
    # if mode is 'sick' and time isn't divisible by 4
    # if mode is 'unpaid' and time isn't divisible by 4
    # if date is more than 7 days from today


    return true

  parseMode = (command) ->
    comps = command.split ' '
    [mode, command] = [comps.shift(), comps.join ' ']
    mode = (mode || '').trim()
    command = (command || '').trim()
    if mode in MODES
      [mode, command]
    else
      ['none', command]

  parseTime = (command, activeStart, activeEnd) ->
    # parse time component
    command = command.trimLeft() || ''
    time = []
    if match = command.match REGEX.rel_time
      if match[0] is 'half-day' or match[0] is 'half day'
        copy = moment(activeStart)
        copy.hour(activeStart.hour() - 4)
        time.push copy, activeEnd
      else if match[0] is 'noon'
        time.push moment({hour: 12, minute: 0})
      else if match[0] is 'midnight'
        time.push moment({hour: 0, minute: 0})
      else
        block = parseFloat match[3]
        time.block = block
      command = command.replace ///#{match[0]} ?///i, ''
    else if match = command.match REGEX.time
      timeMatch = match[0]
      today = moment()
      if hourStr = timeMatch.match /\b(([0-1][0-9])|(2[0-3])):/i
        hour = parseInt (hourStr[0].replace(':', ''))
        if hour <= 12
          isPM = today.format('a') is 'pm'
          if not timeMatch.match /am?|pm?/i
            timeMatch = timeMatch + " #{today.format('a')}"
      today = moment("#{today.format('YYYY-MM-DD')} #{timeMatch}")
      if isPM
        today.add(12, 'hours')
      time.push today
      command = command.replace ///#{match[0]} ?///i, ''
    # else if match = command.match regex for time ranges (???)
    else
      time.push moment()
    [time, command]

  parseDate = (command) ->
    command = command.trimLeft() || ''
    date = []
    if match = command.match /today/i
      date.push moment()
      command = command.replace ///#{match[0]} ?///i, ''
    else if match = command.match /yesterday/i
      yesterday = moment().subtract(1, 'days')
      date.push yesterday
      command = command.replace ///#{match[0]} ?///i, ''
    else if match = command.match REGEX.days
      today = moment()
      if today.format('dddd').toLowerCase() isnt match[0]
        today = today.day(match[0]).subtract(7, 'days')
      date.push today
      command = command.replace ///#{match[0]} ?///i, ''
    else if match = command.match REGEX.date # Placeholder for date blocks
      if match[0].indexOf('-') isnt -1
        dateStrings = match[0].split('-')
        month = ''
        for str in dateStrings
          str = str.trim()
          date.push moment(str, "MMMM DD")
      else
        absDate = moment(match[0], "MMMM DD")
        date.push absDate
      command = command.replace ///#{match[0]} ?///i, ''
    else if match = command.match REGEX.numdate
      if match[0].indexOf('-') isnt -1
        dateStrings = match[0].split('-')
        month = ''
        for str in dateStrings
          str = str.trim()
          date.push moment(str, 'MM/DD')
      else
        absDate = moment(match[0], 'MM/DD')
        date.push absDate
      command = command.replace ///#{match[0]} ?///i, ''
    else
      date.push moment()
    [date, command]

  parseProjects = (command) ->
    projects = []
    command = command.trimLeft() || ''
    command_copy = command.split(' ').slice()

    for word in command_copy
      if word.charAt(0) is '#'
        if project = Organization.getProjectByName word
          projects.push project
        command = command.replace ///#{word} ?///i, ''
      else
        break
    [projects, command]

module.exports = Punch