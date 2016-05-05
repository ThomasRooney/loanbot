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

loansTable = {
  # "PersonA PersonB" ==> PersonA owes personB currency => amount. If amount is negative it implies opposite direction
  "@bob @charlie" : 100,
}

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

addTransaction = (from, to, amount, description, callback) ->
  db.run("INSERT INTO transactions values \
    (?, ?, ?, datetime('now'), ?, ?)",
    [from,
    to,
    amount,
    STATE_PENDING_TO,
    description], () -> callback(@lastID));

confirmTransaction = (person, id, callback) ->
  db.run("UPDATE transactions SET state = ? WHERE (RowId = ? AND state = ? AND [from] = ?) OR (RowId = ? AND state = ? AND [to] = ?)", [
      STATE_CONFIRMED, id, STATE_PENDING_FROM, person, id, STATE_PENDING_TO, person,
  ], (err, data) ->
    from = "NOP"
    to = "NOP"
    amount=100
    callback(err == null, from, to, amount))

getTotals = (callback) ->
  # db.all("SELECT * FROM transactions WHERE state=#{STATE_CONFIRMED}", (err, rows) ->
  db.all("select [from], [to], sum(amount) as total from transactions group by [from], [to] order by 1,2", (err, rows) ->
    if (err)
      console.log(err)

    callback(rows)
  )

transactions = {
  "@charlie": [0: {
      counterparty: "@andy",
      amount: -100,
      confirmed: true
    }]
  "@andy": [0: {
      counterparty: "@charlie",
      amount: 100,
      confirmed: false
    }]
}

toKey = (name1, name2) ->
  if name1 < name2 then name1 + " " + name2 else name2 + " " + name1

# E.g. gave("@bob", "@charlie", 100)
# gave = (from, to, amount, description) ->
  # loanTableKey = toKey(from, to)
  # if from > to
  #   amount *= -1
  # loansTable[loanTableKey] = (loansTable[loanTableKey] + amount) || amount
  # if from > to
  #   return loansTable[loanTableKey]
  # else
  #   return -loansTable[loanTableKey]


module.exports = (robot) ->

  # robot.hear /badger/i, (res) ->
  #   res.send "Badgers? BADGERS? WE DON'T NEED NO STINKIN BADGERS"
  #
  # robot.hear /(@[^\s:]+):?\s+gave\s+(@[^\s:]+):?\s+(\d+)/i, (res) ->
  #   personA = res.match[1].toLowerCase()
  #   personB = res.match[2].toLowerCase()
  #   amount = Number(res.match[3])
  #   newTotal = gave(personA, personB, amount)
  #   if newTotal > 0
  #     res.send("#{personA} now owes #{personB} #{newTotal}")
  #   else
  #     res.send("#{personB} now owes #{personA} #{-newTotal}")

  robot.hear /confirm\s+(\d+)/i, (res) ->
    person = "@" + res.message.user.name
    id = Number(res.match[1])
    confirmTransaction(person, id, (success, from, to, amount) ->
      if success
        res.send("Successfully confirmed transaction #{id} (#{from} gave #{to} #{amount})")
      else
        res.send("Could not successfully confirm transaction")
    )

  robot.hear /gave\s+(@[^\s:]+):?\s+(\d+)/i, (res) ->
    personA = "@" + res.message.user.name
    personB = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = "NOP"
    # newTotal = gave(personA, personB, amount)
    addTransaction(personA, personB, amount, description,
      (transID) ->
        response = "Transaction #{transID} added: #{personA} gave #{amount} to #{personB}.\n" +
          "  #{personB} can confirm with:\n" +
          "    `@loanbot: confirm #{transID}`"
        res.send(response))

  robot.hear /(@[^\s:]+):?\s+gave\s+(\d+)/i, (res) ->
    personB = "@" + res.message.user.name
    personA = res.match[1].toLowerCase()
    amount = Number(res.match[2])
    description = "NOP"
    # newTotal = gave(personA, personB, amount)
    addTransaction(personA, personB, amount, description,
      (transID) ->
        response = "Transaction #{transID} added: #{personA} gave #{amount} to #{personB}.\n" +
          "  #{personA} can confirm with:\n" +
          "    `@loanbot: confirm #{transID}`"
        res.send(response))


  robot.hear /all totals/i, (res) ->
    getTotals((rows) ->
      totals = {}
      for id, row of rows
        totals[row.from] = (totals[row.from] || 0) - row.total
        totals[row.to] = (totals[row.to] || 0) + row.total

      minimize(totals, res)
    )


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
