:params { openAiApiKey: "paste your OpenAI API key here" }, 
  baseURL: "https://raw.githubusercontent.com/neo4j-examples/sec-edgar-notebooks/main/data/sample/"
}
;

////////////////////////////////////////////////
// Load Form 10-K data

CREATE CONSTRAINT unique_form IF NOT EXISTS FOR (n:Form) REQUIRE n.formId IS UNIQUE
;
CREATE CONSTRAINT unique_chunk IF NOT EXISTS 
    FOR (c:Chunk) REQUIRE c.chunkId IS UNIQUE
;
CREATE VECTOR INDEX `form_10k_chunks` IF NOT EXISTS
FOR (c:Chunk) ON (c.textEmbedding) 
OPTIONS { indexConfig: {
  `vector.dimensions`: 1536,
  `vector.similarity_function`: 'cosine'    
}}
;
// Load each individual form 10-K document
LOAD CSV WITH HEADERS from $baseURL + 'form10k/index.csv' AS row
WITH row.filename as filename
CALL {
  WITH filename
  WITH filename, apoc.text.regexGroups(filename,'([^\/]*)\.json')[0][1] AS formId
  CALL apoc.load.json($baseURL + 'form10k/' + filename) YIELD value
  MERGE (f:Form {formId: formId}) 
    ON CREATE SET f = value, f.formId = formId
}
;
// Migrate the form 10-K text to a Chunk
WITH ['item1','item1a','item7','item7a'] as items
UNWIND items as item
CALL {
  WITH item
  MATCH (f:Form)
  WITH f, item, "0000" as chunkSeqId
  WITH f, item, chunkSeqId, f.formId + "-" + item + "-chunk" + chunkSeqId as chunkId
  MERGE (section:Chunk {chunkId: chunkId})
  ON CREATE SET 
      section.chunkSeqId = chunkSeqId,
      section.text = apoc.any.property(f, item)
  MERGE (f)-[:SECTION {f10kItem: item}]->(section)
}
;
// Splt the text into chunks of 1000 words
MATCH (f:Form)-[s:SECTION]->(first:Chunk)
WITH f, s, first
WITH f, s, first, apoc.text.split(first.text, "\s+") as tokens
CALL apoc.coll.partition(tokens, 1000) YIELD value
WITH f, s, first, apoc.text.join(value, " ") as chunk
WITH f, s, first, collect(chunk) as chunks
CALL {
    WITH f, s, first, chunks
    WITH f, s, first, chunks, [idx in range(1, size(chunks) -1) | 
         { chunkId: f.formId + "-" + s.f10kItem + "-chunk" + apoc.number.format(idx, "#0000"), text: chunks[idx] }] as chunkProps 
    CALL apoc.create.nodes(["Chunk"], chunkProps) yield node
    SET first.text = head(chunks)
    MERGE (node)-[:PART_OF]->(f)
    WITH first, collect(node) as chunkNodes
    CALL apoc.nodes.link(chunkNodes, 'NEXT')
    WITH first, head(chunkNodes) as nextNode
    MERGE (first)-[:NEXT]->(nextNode)
}
RETURN f.formId
;
// Generate embeddings for each chunk
:AUTO  
MATCH (chunk:Chunk) WHERE chunk.textEmbedding IS NULL
CALL {
  WITH chunk
  WITH chunk, genai.vector.encode(chunk.text, "OpenAI", {token: $openAiApiKey}) AS vector
  CALL db.create.setNodeVectorProperty(chunk, "textEmbedding", vector)    
} IN TRANSACTIONS OF 10 ROWS
;
////////////////////////////////////////////////////////////////
// Load Form 13 data
CREATE CONSTRAINT unique_company 
    IF NOT EXISTS FOR (com:Company) 
    REQUIRE com.cusip6 IS UNIQUE
;
CREATE CONSTRAINT unique_manager 
  IF NOT EXISTS
  FOR (n:Manager) 
  REQUIRE n.managerCik IS UNIQUE
;
CREATE FULLTEXT INDEX fullTextManagerNames
  IF NOT EXISTS
  FOR (mgr:Manager) 
  ON EACH [mgr.managerName]
;
LOAD CSV WITH HEADERS FROM $baseURL + "form13.csv" as row
MERGE (com:Company {cusip6: row.cusip6})
  ON CREATE SET com.companyName = row.companyName,
                com.cusip = row.cusip
MERGE (mgr:Manager {managerCik: row.managerCik})
    ON CREATE SET mgr.managerName = row.managerName,
            mgr.managerAddress = row.managerAddress
MERGE (mgr)-[owns:OWNS_STOCK_IN { 
    reportCalendarOrQuarter: row.reportCalendarOrQuarter }]->(com)
    ON CREATE
      SET owns.value  = toFloat(row.value), 
          owns.shares = toInteger(row.shares)
;
MATCH (com:Company), (form:Form)
  WHERE com.cusip6 = form.cusip6
SET com.names = form.names
MERGE (com)-[:FILED]->(form)
;