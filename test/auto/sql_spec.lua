local P = require'plenary.path'
local curl = require'plenary.curl'
local eq = assert.are.same
local sql = require'sql'
local u = require'sql.utils'

describe("sql", function()
  local path = "/tmp/db.sqlite3"
  vim.loop.fs_unlink(path)

  describe('.new', function()
    it('should create sql.nvim without opening connection', function()
      local tmp = "/tmp/db4.db"
      local db = sql.new(tmp)
      eq("table", type(db), "should return sql.nvim object")
      eq(nil, db.conn, "connection shuld be nil")
      eq("table", type(db:open()), "should return sql.nvim object")
      eq(true, db:isopen(), "should be opened")
      eq(0, db:status().code, "should be be zero")
      eq(true, db:eval("create table if not exists a(title)"), "should be create a table")
      eq(true, db:eval("insert into a(title) values('new')"), "should be insert stuff")
      eq("table", type(db:eval("select * from a")), "should be have content")
      eq(true, db:close(), "should close")
      eq(true, db:isclose("select * from a"), "should close")
      eq(true, P.exists(P.new(tmp)), "It should created the file")
      vim.loop.fs_unlink(tmp)
    end)
  end)

  describe(":open/:close", function() -- todo(tami5): change to open instead of connect.
    it('creates in memory database.', function()
      local db = sql.open()
      eq("table", type(db), "returns new main interface object.")
      eq("cdata", type(db.conn), "returns sql object.")
      assert(db:close(), "returns true if the connection is closed successfully.")
    end)

    it("creates new persistence database.", function()
      local db = sql:open(path)
      eq("cdata", type(db.conn), "returns sqlite object.")

      eq(true, db:eval("create table if not exists todo(title text, desc text, created int)"))

      db:insert("todo", {
        { title = "1", desc = "......", created = 2021 },
        { title = "2", desc = "......", created = 2021 }
      })

      eq(true, db:close(), "It should close connection successfully.")
      eq(true, P.exists(P.new(path)), "It should created the file")
    end)

    it("connects to pre-existent database.", function()
      local db = sql:open(path)

      local todos = db:eval("select * from todo")
      eq("1", todos[1].title)
      eq("2", todos[2].title)

      eq(true, db:close(), "It should close connection successfully.")
      eq(true, P.exists(P.new(path)), "File should still exists")
      vim.loop.fs_unlink(path)
    end)

    it('returns data and time of creation', function()
      local db = sql:open()
      eq(os.date('%Y-%m-%d %H:%M:%S'), db.created)
      db:close()
    end)

    it(':open and .open work the same', function()
      local db = sql.open()
      eq("cdata", type(db.conn), "returns sql object.")
      eq(true, db:close(), "it should closes")
      local db2 = sql:open()
      eq("cdata", type(db2.conn), "returns sql object.")
      eq(true, db2:close(), "it should closes")
    end)

    it('reopen db object.', function()
      local db = sql:open(path)
      local row = {title = "1", desc = "...."}
      db:eval("create table if not exists todo(title text, desc text)")
      db:insert("todo", row)

      db:close()
      eq(true, db.closed, "should be closed." )

      db:open()
      eq(false, db.closed, "should be reopend." )

      eq(path, db.uri, "uri should be identical to db.uri" )
      local res = db:eval("select * from todo")
      eq(row, res[1], vim.loop.fs_unlink(path), "local row should equal db:eval result.")
    end)
  end)

  describe(':open_with', function()
    it('works with initalized sql objects.', function()
      local db = sql:open(path)

      db:eval("create table if not exists todo(title text, desc text)")
      db:insert("todo", { title = "1", desc = "...." })
      db:close()
      eq(true, db.closed, "should be closed.")

      local res = db:with_open(function()
        return db:eval("select * from todo")
      end)
      eq(true, db.closed, "should be closed.")
      eq("1", res[1].title, "should pass.")

      vim.loop.fs_unlink(path)
    end)

    it('works without initalizing sql objects. (via uri)', function()
      local res = sql.with_open(path, function(db)
        db:eval("create table if not exists todo(title text, desc text)")
        db:insert("todo", { title = "1", desc = "...." })
        return db:eval("select * from todo")
      end)
      eq("1", res[1].title, "should pass.")
    end)
  end)

  describe(':isopen/isclose', function()
    local db = sql:open()
    it('returns true if the db connection is open', function()
      assert(db:isopen())
    end)
    it('returns true if the db connection is closed', function()
      db:close()
      assert(db:isclose())
    end)
  end)

  describe(':status', function()
    local db = sql:open()
    local status = db:status()
    it('returns status code of the last filed call', function()
      eq("number", type(status.code), "it should return sqlite last flag code")
    end)

    it('returns error message of the last filed call', function()
      eq("string", type(status.msg), "it should return sqlite last errmsg")
    end)


    it('return whether the connection is closed or still open', function()
      assert(not status.closed, "it should return connection status")
      db:close()
    end)
  end)

  describe(":eval", function()
    local db = sql:open()
    it('It evaluate should basic sqlite statement', function()
      eq(true, db:eval("create table people(id integer primary key, name text, age  integer)"))
    end)

    it('returns true if the operation is successful', function()
      eq(true, db:eval("create table if not exists todos(id, title text, desc text, created int)"))
    end)

    local row = {
      {
        id = 1,
        title = "Create something",
        desc = "Don't you dare to tell conni",
        created = os.time()
      },
      {
        id = 2,
        title = "Don't work on something else",
        desc = "keep conni close by :P",
        created = os.time()
      }
    }

    it('inserts lua table.', function()
      eq(true, db:eval("insert into todos(id, title,desc,created) values(:id, :title, :desc, :created)",
      row[1]))
    end)

    it('selects everything from table and return lua table if only one row.', function()
      local res = db:eval("select * from todos")
      eq(row[1], res[1])
    end)

    it('deletes from sql tables', function()
      eq(true, db:eval("delete from todos"), "It should delete table content")
    end)

    it('inserts nested lua table.', function()
      eq(true, db:eval("insert into todos(id,title,desc,created) values(:id, :title, :desc, :created)", row))
      eq(row, db:eval("select * from todos"), "should equal")
    end)

    it('return a lua table by id', function()
      local res
      res = db:eval("select * from todos where id = :id", { id = 1 })
      eq(row[1], res[1], "with named params")

      res = db:eval("select * from todos where id = ?", { 1 })
      eq(row[1], res[1], "with unamed params")

      res = db:eval("select * from todos where id = ?",  1)
      eq(row[1], res[1], "with single value")
    end)
    it('return the lua table with where and or', function()
      eq(row, db:eval("select * from todos where id = 1 or id = 2 or id = 3"))
    end)
    it('update by id', function()
      eq(true, db:eval("update todos set desc = :desc where id = :id", {
        id = 1,
        desc = "..."
      }), "it works with named params")
      eq(true, db:eval("update todos set desc = ? where id = ?", {
        2,
        "..."
      }), "it works with unnamed params")
    end)

    it('delete by id', function()
      eq(true, db:eval("delete from todos where id = :id", { id = 2 }))
      eq(true, db:eval("delete from todos where id = :id", { id = 1 }))
    eq(true, db:eval("select * from todos"), "It should be empty by now.")
    end)
    db:close()
  end)

  describe(':insert', function()
    local db = sql:open()
    assert(db:eval("create table todos(title text, desc text)"))

    it('works with table_name being as the first argument', function()
      db:insert("todos", {
        title = "TODO 1",
        desc = "................",
      })
      local results = db:eval("select * from todos")
      eq(true, type(results) == "table", "It should be inserted.")
      eq("TODO 1", results[1].title)
      eq("................", results[1].desc)
      db:eval("delete from todos")
    end)

    it('inserts multiple rows in a sql_table (with tbl_name being first param)', function()
      db:insert("todos", {
        {
          title = "todo 3",
          desc = "...",
        },
        {
          title = "todo 2",
          desc = "...",
        },
        {
          title = "todo 1",
          desc = "...",
        },
      })
      local store = db:eval("select * from todos")
      eq(3, vim.tbl_count(store))
      for _, v in ipairs(store) do
        eq(true, v.desc == "...")
      end
      db:eval("delete from todos")
    end)

    db:close()
  end)

  describe(':update', function()
    local db = sql:open()
    assert(db:eval("create table todos(title text, desc text)"))

    it('works with table_name being as the first argument', function()
      db:insert("todos", {
        title = "TODO 1",
        desc = "................",
      })
      db:update("todos", {
        values = { desc = "done" },
        where = { title = "TODO 1" },
      })
      local results = db:eval("select * from todos")
      eq(true, type(results) == "table", "It should be inserted.")
      eq("TODO 1", results[1].title)
      eq("done", results[1].desc)
      db:eval("delete from todos")
    end)

    it('works with table_name being a lua table key', function()
      db:insert("todos",{
        title = "TODO 1",
        desc = " .......... ",
      })

      db:update("todos", {
        values = { desc = "not done" },
        where = { title = "TODO 1" },
      })

      local results = db:eval("select * from todos")
      eq(true, type(results) == "table", "It should be inserted.")
      eq("TODO 1", results[1].title)
      eq("not done", results[1].desc)
      db:eval("delete from todos")
    end)

    it('update multiple rows in a sql table', function()
      db:eval("delete from todos")
      db:insert("todos", {
        {
          title = "todo 3",
          desc = "...",
        },
        {
          title = "todo 2",
          desc = "...",
        },
        {
          title = "todo 1",
          desc = "...",
        },
      })
      db:update("todos", {
        {
          values = { desc = "not done" },
          where = { title = "todo 1" },
        },
        {
          values = { desc = "done" },
          where = { title = "todo 2" },
        },
        {
          values = { desc = "almost done" },
          where = { title = "todo 3" },
        }
      })

      local store = db:eval("select * from todos")
      eq(3, vim.tbl_count(store))
      for _, v in ipairs(store) do
        eq(true, v.desc ~= "...")
      end
      db:eval("delete from todos")
    end)

    it('skip updating if opts is nil', function()
      db:update("todos")
    end)
    db:close()
  end)

  describe(':delete', function()
    local db = sql:open()
    assert(db:eval("create table todos(title text, desc text)"))

    it('works with table_name being as the first argument', function()
      db:insert("todos", {
        title = "TODO 1",
        desc = "................",
      })
      db:delete('todos')
      local results = db:eval("select * from todos")
      eq(false, type(results) == "table", "It should be deleted.")
    end)

    it('works with table_name being and where', function()
      db:insert("todos", {
        {
          title = "TODO 1",
          desc = "................",
        },
        {
          title = "TODO 2",
          desc = "................",
        }
      })
      db:delete('todos', { where = { title = "TODO 1" }})
      local results = db:eval("select * from todos")
      eq(true, type(results) == "table")
      eq("TODO 2", results[1].title)
      eq("................", results[1].desc)
    end)

    it('delete multiple keys with list of ors', function()
      db:insert("todos", {
        {
          title = "TODO 1",
          desc = "................",
        },
        {
          title = "TODO 2",
          desc = "................",
        }
      })
      db:delete("todos", { { where = { title = {"TODO 1", "TODO 2"} } } })
      local results = db:eval("select * from todos")
      eq(false, type(results) == "table")
    end)

    it('delete multiple keys with dict for each conditions.', function()
      db:insert("todos", {
        {
          title = "TODO 1",
          desc = "................",
        },
        {
          title = "TODO 2",
          desc = "................",
        }
      })
      db:delete('todos', { { where = { title = "TODO 1" } }, { where = {title = "TODO 2"} } })
      local results = db:eval("select * from todos")
      eq(false, type(results) == "table")
    end)
    db:close()
  end)

  describe(':select', function()
    local db = sql.open(path)
    local posts = vim.fn.json_decode(curl.get("https://jsonplaceholder.typicode.com/posts").body)
    local users = vim.fn.json_decode(curl.get("https://jsonplaceholder.typicode.com/users").body)
    it('.... pre', function()
      for _, user in ipairs(users) do -- Not sure how to deal with nested tables now
        user["address"] = nil
        user["company"] = nil
      end
      assert(db:eval("create table posts(id int not null primary key, userId int, title text, body text);"))
      assert(db:eval("create table users(id int not null primary key, name text, email text, phone text, website text, username text);"))
      eq(true, db:insert("users", users))
      eq(true, db:insert("posts", posts))
      eq("table", type(db:eval("select * from posts")), "there should be posts")
      eq("table", type(db:eval("select * from users")), "there should be users")
    end)

    it('return everything with no params', function()
      eq(posts, db:select("posts"))
    end)

    it('return everything that matches where closure', function()
      local res = db:select("posts", {
        where  = {
          id = 1
        }
      })
      local expected = (function()
        for _, post in ipairs(posts) do
          if post["id"] == 1 then
            return post
          end
        end
      end)()

      eq(expected, res[1])
    end)

    it('join tables.', function()
      local res = db:select("posts", {
        where  = { id = 1 },
        join = {
          posts = "userId",
          users = "id"
        }
      })
      local expected = (function()
        for _, post in ipairs(posts) do
          if post["id"] == 1 then
            return u.tbl_extend("keep", post, (function()
            for _, user in ipairs(users) do
              if user["id"] == post["userId"] then
                return user
              end
            end
            end)())
          end
        end
      end)()

      eq(expected, res[1])
    end)

    it('return selected keys only', function()
      local res = db:select("posts", {
        where  = { id = 1 },
        select = { "userId", "posts.body" }
      })
      local expected = (function()
        for _, post in ipairs(posts) do
          if post["id"] == 1 then
            return {
              userId = post["userId"],
              body = post["body"],
            }
          end
        end
      end)()

      eq(expected, res[1])
    end)

    db:close()
  end)

  describe(':schema', function()
    local db = sql.open()
    db:eval("create table test(a text, b int)")

    it('gets a sql table schema', function()
      local sch = db:schema("test")
      eq({ a = "text", b = "int" }, sch)
    end)

    it('gets a sql table schema keys only', function()
      local sch = db:schema("test", true)
      eq({"a", "b"}, sch)
    end)

    db:close()
  end)

  describe(':create', function()
    local db = sql.open()

    it('create a new sqlite table, and return true', function()
      eq(false, db:exists("test"))
      db:create("test", {
        id = {"integer", "primary", "key"},
        title = "text",
        desc = "text",
        created = "int",
        done = {"int", "not", "null", "default", 0},
      })
      eq(true, db:exists("test"))
    end)

    it("won't override the table schema if it exists", function()
      db:create("test", {id = "not_a_type", ensure = true})
      local sch = db:schema("test")
      eq("text", sch.title, "should not be nil")
    end)
    db:close()
  end)

  describe(':drop', function()
    local db = sql.open()

    it('should drop empty tables.', function()
      db:create("test", { a = "text", b = "int" })
      eq(true, db:exists("test"), "should exists")
      db:drop("test")
      eq(true, not db:exists("test"), "shout be dropped")
    end)

    it('should drop non-empty tables.', function()
      db:create("test", { a = "text", b = "int" })
      db:eval("insert into test(a,b) values(?,?)", {"a", 3})
      eq(true, db:exists("test"), "should exists")
      db:drop("test")
      eq(true, not db:exists("test"), "shout be dropped")
    end)
    db:close()
  end)

end)
