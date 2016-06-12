sqlite3 = require('sqlite3').verbose();
db = new sqlite3.Database('db.sqlite');

# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md

# gave @andy 1000000
# ID == enumerated number
# @loanbot @andy, confirm @bob gave you 100000 with @confirm <ID>

# commands


# (Andy Says:) @loanbot pending
# Waiting on your confirmation for these transactions:
# 0: @Bob gave you 100 (confirm 0)
# 1: @Charlie gave you 200 (confirm 1)
# 2: you gave @Bob 300 (confirm 2)
# (@confirm)

# (Andy Says:) @loanbot transactions
# Your transactions:
# <DATETIME>: @Bob gave you 100 "For coffee"
# <DATETIME>: @Charlie gave you 200
# <DATETIME>: you gave @Charlie 200 "For beer" (pending)
# <DATETIME>: you gave @Bob 100 (pending)
# <DATETIME>: @charlie gave you 200

# (Andy Says:) @loanbot transactions @Bob
# Your transactions:
# <DATETIME>: @Bob gave you 100 "For coffee"
# <DATETIME>: you gave @Bob 100 (pending)
# <DATETIME>: @charlie gave you 200



# Andy: @loanbot totals @charlie
# > You owe Bob 300

# Andy: @loanbot totals
# > You owe Bob 300
# > Charlie owes you 100

# Andy: @loanbot all totals
# > You owe Bob 300
# > Charlie owes you 100
# > Charlie owes Bob 100

# @loanbot reconcile
# > You owe Bob 100
# > You owe Charlie 300

# @loanbot confirm

# @loanbot confirm 3

# state of a transaction is
STATE_PENDING_FROM = 0
STATE_PENDING_TO = 1
STATE_CONFIRMED = 2
STATE_DENIED = 3

stateToDescription = (state, from, to) ->
  if state == STATE_PENDING_FROM
    return "(pending confirmation from #{from})"
  if state == STATE_PENDING_TO
    return "(pending confirmation from #{to})"
  if state == STATE_CONFIRMED
    return ""
  if state == STATE_DENIED
    return "(denied)"

addTransactionToDB = (from, to, pendingState, amount, description, callback) ->
  db.run("INSERT INTO transactions values \
    (?, ?, ?, datetime('now'), ?, ?)",
    [from,
    to,
    amount,
    pendingState,
    description], () -> callback(@lastID));

setState = (state, person, id, callback) ->
  db.run("UPDATE transactions SET state = ? WHERE (RowId = ? AND state = ? AND [from] = ?) OR (RowId = ? AND state = ? AND [to] = ?)", [
      state, id, STATE_PENDING_FROM, person, id, STATE_PENDING_TO, person,
  ], (err, data) ->
    if err == null
      db.get("SELECT [from], [to], amount FROM transactions WHERE RowId = ? AND state = ? ", [id, state], (err, row) ->
        if err == null and row
          callback(true, row.from, row.to, row.amount)
        else
          callback(false)
      )
    else
      callback(false))

getTotals = (person1, person2, callback) ->
  query = "SELECT [from], [to], sum(amount) as total FROM transactions WHERE state=#{STATE_CONFIRMED}"

  if person1
    query += " AND ([from] = '#{person1}' OR [to] = '#{person1}')"

  if person2
    query += " AND ([from] = '#{person2}' OR [to] = '#{person2}')"

  query += " GROUP BY [from], [to] ORDER BY 1,2"

  console.log(query)

  db.all(query, (err, rows) ->
    if (err)
      console.log(err)

    callback(rows)
  )

getTransactions = (person1, person2, pending, waiting, callback) ->
  query = "SELECT RowId, * FROM transactions"
  wheres = []

  if (person1)
    wheres.push("([from] = '#{person1}' OR [to] = '#{person1}')")
  if person2
    wheres.push("([from] = '#{person2}' OR [to] = '#{person2}')")

  if pending and waiting
    wheres.push("(state = #{STATE_PENDING_TO} OR state = #{STATE_PENDING_FROM})")
  else if pending
    wheres.push("state = #{STATE_PENDING_FROM}")
  else if waiting
    wheres.push("state = #{STATE_PENDING_TO}")

  if (wheres.length > 0)
    query += " WHERE "
    query += wheres.join(" AND ")

  console.log(query)

  db.all(query, (err, rows) ->
    if (err)
      console.log(err)

    callback(rows)
  )

handleTransactionAdded = (res, transID, personA, personB, amount, description) ->
  console.log(transID, personA, personB, amount, description, res.message.user.name)

  origin = "@" + res.message.user.name
  if personA == origin
    target = personB
    dm = "#{personA} gave you #{amount}"
  else
    target = personA
    dm = "You gave #{amount} to #{personB}"

  if description
    dm += " for #{description}"

  dm += "\n" +
      "Confirm with:\n" +
      "    `confirm #{transID}`"

  room = target.substr(1) # Remove the @
  res.robot.messageRoom room, dm

  response = "Transaction #{transID} added: #{personA} gave #{amount} to #{personB}.\n" +
          "  #{target} can confirm with:\n" +
          "    `@loanbot: confirm #{transID}`"
  res.robot.messageRoom "lending", response
module.exports = (robot) ->
  # confirm #
  robot.hear /confirm\s+(\d+)/i, (res) ->
    person = "@" + res.message.user.name
    id = Number(res.match[1])
    setState(STATE_CONFIRMED, person, id, (success, from, to, amount) ->
      if success
        res.send("Transaction confirmed #{id} (#{from} gave #{amount} to #{to})")
      else
        res.send("Could not successfully confirm transaction #{id}")
    )

  # deny #
  robot.hear /deny\s+(\d+)/i, (res) ->
    person = "@" + res.message.user.name
    id = Number(res.match[1])
    setState(STATE_DENIED, person, id, (success, from, to, amount) ->
      if success
        res.send("Successfully denied transaction #{id} (#{from} gave #{amount} to #{to})")
      else
        res.send("Could not successfully deny transaction #{id}")
    )

  # gave @person amount description
  robot.hear /^(?:I\s)?gave\s+([^\s:]+):?\s+(\d+)\s+(?:for\s)?(.+)/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = res.match[3]

    addTransaction(res, personA, personB, STATE_PENDING_TO, amount, description)


  # gave @person amount
  robot.hear /^(?:I\s)?gave\s+([^\s:]+):?\s+(\d+)$/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = ""

    addTransaction(res, personA, personB, STATE_PENDING_TO, amount, description)


  # person gave amount description
  robot.hear /^([^\s:]+):?\s+gave\s+(?:me\s)?(\d+)\s+(?:for\s)?(.+)/i, (res) ->
    personB = "@" + res.message.user.name
    personA = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = res.match[3]

    addTransaction(res, personA, personB, STATE_PENDING_FROM, amount, description)


  # person gave amount
  robot.hear /^([^\s:]+):?\s+gave\s+(?:me\s)?(\d+)$/i, (res) ->
    personB = "@" + res.message.user.name
    personA = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = ""

    addTransaction(res, personA, personB, STATE_PENDING_FROM, amount, description)


  # pending
  robot.hear /^\s*pending$/i, (res) ->
    personA = "@" + res.message.user.name
    getTransactions(personA, null, true, false, (rows) ->
      response = "Pending transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # pending @person
  robot.hear /^\s*pending\s+(@[^\s:]+):?/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    console.log(personA, personB);
    getTransactions(personA, personB, true, false, (rows) ->
      response = "Pending transactions with #{personA}:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # all pending -> Same as all waiting
  robot.hear /^\s*all pending$/i, (res) ->
    getTransactions(null, null, true, true, (rows) ->
      response = "All pending transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # waiting
  robot.hear /^\s*waiting$/i, (res) ->
    personA = "@" + res.message.user.name
    getTransactions(personA, null, false, true, (rows) ->
      response = "Waiting transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # waiting @person
  robot.hear /^\s*waiting\s+(@[^\s:]+):?/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    getTransactions(personA, personB, false, true, (rows) ->
      response = "Waiting transactions with #{personA}:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # all waiting -> Same as all pending
  robot.hear /^\s*all waiting$/i, (res) ->
    getTransactions(null, null, true, true, (rows) ->
      response = "All waiting transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )


  # transactions
  robot.hear /^\s*transactions$/i, (res) ->
    personA = "@" + res.message.user.name
    getTransactions(personA, null, null, false, (rows) ->
      response = "Transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # transactions @person
  robot.hear /^\s*transactions\s+(@[^\s:]+):?/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    console.log(personA, personB);
    getTransactions(personA, personB, null, false, (rows) ->
      response = "Transactions with #{personA}:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )

  # all transactions
  robot.hear /^\s*all transactions$/i, (res) ->
    getTransactions(null, null, null, false, (rows) ->
      response = "All transactions:\n"
      for id, row of rows
        console.log(id, row)
        response += "#{row.rowid} #{row.timestamp} #{row.from} gave #{row.amount} to #{row.to}: #{row.description} #{stateToDescription(row.state,row.from,row.to)}\n"

      res.send(response)
    )


  # totals
  robot.hear /^\s*totals$/i, (res) ->
    personA = "@" + res.message.user.name

    getTotals(personA, null, (rows) ->
      totals = {}
      for id, row of rows
        totals[row.from] = (totals[row.from] || 0) - row.total
        totals[row.to] = (totals[row.to] || 0) + row.total

      minimize(totals, res)
    )

  # totals person
  robot.hear /^\s*totals\s+(@[^\s:]+):?/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()

    getTotals(personA, personB, (rows) ->
      totals = {}
      for id, row of rows
        totals[row.from] = (totals[row.from] || 0) - row.total
        totals[row.to] = (totals[row.to] || 0) + row.total

      minimize(totals, res)
    )

  # all totals
  robot.hear /^\s*all totals$/i, (res) ->
    getTotals(null, null, (rows) ->
      totals = {}
      for id, row of rows
        totals[row.from] = (totals[row.from] || 0) - row.total
        totals[row.to] = (totals[row.to] || 0) + row.total

      minimize(totals, res)
    )

  # Validation
  validateUser = (res, name) ->
    if name[0] != "@"
      res.send("#{name} is invalid. Please use a Slack username starting with @.")
    else if name == "loanbot"
      res.send("Sorry, you can't borrow money from @loanbot")
    else if !robot.brain.userForName(name.substr(1))
      res.send("#{name} is not a valid user")
    else
      return true

  # Add a transaction
  addTransaction = (res, personA, personB, state, amount, description) ->
    console.log("Transaction", personA, personB, state, amount, description)

    selfAt = "@" + res.message.user.name
    if (personA == selfAt and personB == selfAt)
      res.send('You cannot add a transaction with yourself')
    else if (validateUser(res, personA) and validateUser(res, personB))
      addTransactionToDB(personA, personB, state, amount, description, (transID) ->
          handleTransactionAdded(res, transID, personA, personB, amount, description)
        )

  # Minifying code
  findMin = (totals) ->
    min = ''
    for key, value of totals
      if value < (totals[min] || 0)
        min = key

    return min

  findMax = (totals) ->
    max = ''
    for key, value of totals
      if value > (totals[max] || 0)
        max = key
    return max

  minimizeOne = (totals, transactions) ->
    maxDebit = findMin(totals)
    maxCredit = findMax(totals)

    if !maxDebit || !maxCredit
      return true

    minAmt = Math.min(Math.abs(totals[maxDebit]), Math.abs(totals[maxCredit]))

    totals[maxDebit] += minAmt;
    totals[maxCredit] -= minAmt;

    transactions.push({
      from: maxCredit,
      to: maxDebit,
      amount: minAmt
    })

    if totals[maxDebit] == 0
      delete totals[maxDebit]

    if totals[maxCredit] == 0
      delete totals[maxCredit]

    return false

  minimize = (totals, res) ->
    numTransactions = 0
    transactions = []
    while (numTransactions += 1) < 10000
      if minimizeOne(totals, transactions)
        break

    response = "Minimized totals:\n"

    for i, transaction of transactions
      response += "#{transaction.from} owes #{transaction.to} #{transaction.amount}\n"

    res.send(response)

  # all totals
  robot.hear /^help$/i, (res) ->
    res.send("Loanbot commands:\n" +
             "*gave*: Add a transaction. Examples: \n" +
             "           `gave @user 20 description`\n" +
             "           `@user gave 20 description`\n\n" +
             "*pending*: List transactions waiting for you to confirm\n" +
             "*pending @user*: List your transactions with @user waiting for you to confirm\n" +
             "*all pending*: List all transactions waiting to be confirmed\n\n" +
             "*waiting*: List your transactions waiting for someone else to confirm\n" +
             "*waiting @user*: List your transactions waiting for @user to confirm\n" +
             "*all waiting*: List all transactions waiting to be confirmed\n\n" +
             "*transactions*: List all your transactions\n" +
             "*transactions @user*: List your transactions with @user\n" +
             "*all transactions*: List all transactions\n\n" +
             "*totals*: List total amounts owed by or to you\n" +
             "*totals @user*: List total amount owed between you and @user\n" +
             "*all totals*: List total amounts between everyone\n\n" +
             ""
    )

  #
  # robot.respond /resolve\s+(@[^\s:]+)/i (res) ->
  #   res.send
  # robot.hear /I like pie/i, (res) ->
  #   res.emote "makes a freshly baked pie"
  #
  # lulz = ['lol', 'rofl', 'lmao']
  #
  # robot.respond /lulz/i, (res) ->
  #   res.send res.random lulz
  #
  # robot.topic (res) ->
  #   res.send "#{res.message.text}? That's a Paddlin'"
  #
  #
  # enterReplies = ['Hi', 'Target Acquired', 'Firing', 'Hello friend.', 'Gotcha', 'I see you']
  # leaveReplies = ['Are you still there?', 'Target lost', 'Searching']
  #
  # robot.enter (res) ->
  #   res.send res.random enterReplies
  # robot.leave (res) ->
  #   res.send res.random leaveReplies
  #
  # answer = process.env.HUBOT_ANSWER_TO_THE_ULTIMATE_QUESTION_OF_LIFE_THE_UNIVERSE_AND_EVERYTHING
  #
  # robot.respond /what is the answer to the ultimate question of life/, (res) ->
  #   unless answer?
  #     res.send "Missing HUBOT_ANSWER_TO_THE_ULTIMATE_QUESTION_OF_LIFE_THE_UNIVERSE_AND_EVERYTHING in environment: please set and try again"
  #     return
  #   res.send "#{answer}, but what is the question?"
  #
  # robot.respond /you are a little slow/, (res) ->
  #   setTimeout () ->
  #     res.send "Who you calling 'slow'?"
  #   , 60 * 1000
  #
  # annoyIntervalId = null
  #
  # robot.respond /annoy me/, (res) ->
  #   if annoyIntervalId
  #     res.send "AAAAAAAAAAAEEEEEEEEEEEEEEEEEEEEEEEEIIIIIIIIHHHHHHHHHH"
  #     return
  #
  #   res.send "Hey, want to hear the most annoying sound in the world?"
  #   annoyIntervalId = setInterval () ->
  #     res.send "AAAAAAAAAAAEEEEEEEEEEEEEEEEEEEEEEEEIIIIIIIIHHHHHHHHHH"
  #   , 1000
  #
  # robot.respond /unannoy me/, (res) ->
  #   if annoyIntervalId
  #     res.send "GUYS, GUYS, GUYS!"
  #     clearInterval(annoyIntervalId)
  #     annoyIntervalId = null
  #   else
  #     res.send "Not annoying you right now, am I?"
  #
  #
  # robot.router.post '/hubot/chatsecrets/:room', (req, res) ->
  #   room   = req.params.room
  #   data   = JSON.parse req.body.payload
  #   secret = data.secret
  #
  #   robot.messageRoom room, "I have a secret: #{secret}"
  #
  #   res.send 'OK'
  #
  # robot.error (err, res) ->
  #   robot.logger.error "DOES NOT COMPUTE"
  #
  #   if res?
  #     res.reply "DOES NOT COMPUTE"
  #
  # robot.respond /have a soda/i, (res) ->
  #   # Get number of sodas had (coerced to a number).
  #   sodasHad = robot.brain.get('totalSodas') * 1 or 0
  #
  #   if sodasHad > 4
  #     res.reply "I'm too fizzy.."
  #
  #   else
  #     res.reply 'Sure!'
  #
  #     robot.brain.set 'totalSodas', sodasHad+1
  #
  # robot.respond /sleep it off/i, (res) ->
  #   robot.brain.set 'totalSodas', 0
  #   res.reply 'zzzzz'
