---------------------------------------------------------------------------
--
-- Lua Foreign Data Wrapper for PostgreSQL
--
-- Copyright (c) 2016 Sean Pringle (lua_fdw)
--
-- This software is released under the PostgreSQL Licence
--
-- Author: Sean Pringle <sean.pringle@gmail.com> (lua_fdw)
--
---------------------------------------------------------------------------

-- https://luarocks.org/#quick-start
-- https://github.com/DhavalKapil/elasticsearch-lua

json = require('cjson')
elasticsearch = require("elasticsearch")

remap = { }
proto = "http"
host = "localhost"
port = 9200
index = nil

function EstimateRowCount ()
  return 1
end

function EstimateRowWidth ()
  return string.len("hello world")
end

function EstimateStartupCost ()
  return 1.0
end

function EstimateTotalCost ()
  return EstimateRowCount()
end

function ScanStart ()

  client = elasticsearch.client({
    hosts = {
      {
        protocol = proto,
        host = host,
        port = port
      }
    },
  })

  filters = { }

  for i, clause in ipairs(fdw.clauses) do

    local field = remap[clause.column] or clause.column
    local value = clause.constant

    if clause.operator == "like" then
      value = clause.constant:gsub("%%", "*")
      table.insert(filters, { match = { [field] = value }})
    end

    if fdw.columns[clause.column] == "timestamp" then
      value = clause.constant:gsub(" ", "T")
    end

    if clause.operator == "eq" then
      table.insert(filters, { term = { [field] = value }})
    end
    if clause.operator == "lt" then
      table.insert(filters, { range = { [field] = { lt = value }}})
    end
    if clause.operator == "gt" then
      table.insert(filters, { range = { [field] = { gt = value }}})
    end
    if clause.operator == "lte" then
      table.insert(filters, { range = { [field] = { lte = value }}})
    end
    if clause.operator == "gte" then
      table.insert(filters, { range = { [field] = { gte = value }}})
    end
  end

--  fdw.ereport(fdw.WARNING, json.encode(fdw.clauses))

  data, err = client:search({
    index = index,
    search_type = "scan",
    scroll = "1m",
    body = {
      query = {
        bool = {
          filter = filters,
        }
      }
    }
  })

  if data == nil then
    fdw.ereport(fdw.ERROR, err)
  else
    scroll_id = data["_scroll_id"]
    data = { }
  end
end

function ScanIterate ()

  if #data == 0 and scroll_id then

    local chunk, err = client:scroll({
      scroll_id = scroll_id,
      scroll = "1m",
    })

    if chunk and #chunk["hits"]["hits"] > 0 then
      data = chunk["hits"]["hits"]
    end
  end

  if #data > 0 then
    local cell = table.remove(data, #data)
    local row = { }
    for column, data_type in pairs(fdw.columns) do
      local field = remap[column] or column
      row[column] = cell["_source"][field]
    end
    return row
  end
end

function ScanEnd ()
  client:clearScroll({
    scroll_id = scroll_id
  })
end

function ScanRestart ()
  ScanEnd()
  ScanStart()
end

function ScanExplain ()
  return json.encode(filters)
end
