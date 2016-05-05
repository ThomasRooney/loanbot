var sqlite3 = require('sqlite3').verbose();
var db = new sqlite3.Database('db.sqlite');

var creationStmt = "CREATE TABLE transactions ( \
  [from] varchar(255), \
  [to] varchar(255), \
  amount int, \
  timestamp DATETIME, \
  state int, \
  description varchar(255) \
);"

var index1 = "CREATE INDEX fromIndex \
on transactions ([from]);"

var index2 = "CREATE INDEX toIndex \
on transactions ([to]);"

var index3 = "CREATE INDEX confirmedIndex \
on transactions (confirmed);"

db.serialize(function() {
  db.run(creationStmt);
  // db.run(index1);
  // db.run(index2);
  // db.run(index3);
  // db.run("INSERT INTO transactions values ('@jay', '@jon', 100, datetime('now'), 0, 'services rendered')");
});

db.close();