// Module parameter definitions (using client-side command for Neo4j Browser/Query)
:params { 
  moduleName: "LoadEdgarKG",
  openAiApiKey: "paste your OpenAI API key here", 
  baseURL: "https://raw.githubusercontent.com/neo4j-examples/sec-edgar-notebooks/main/data/sample/"
}
;
/**
  * Load Form 10-K and Form 13 data from remote CSV files.
  * 
  * The process is:
  * 
  * 1. Load Form 10-K data from json files, creatinge one `(:Form)` per file
  * 2. Migrate the text sections of the Form 10-K to `(:Chunk)` nodes, one per section
  * 3. Connect `(:Form)-[:SECTION]->(:Chunk)` relationships
  * 4. Split each section text into chunks of 1000 words and create a `(:Chunk)` for each chunk
  * 5. Create a linked list of `(:Chunk)-[:NEXT]->(:Chunk)` relationships
  * 6. Generate embeddings for each chunk using the OpenAI API
  * 7. Load Form 13 data from a CSV file, creating `(:Company)` and `(:Manager)` nodes
  * 8. Create `(:Manager)-[:OWNS_STOCK_IN]->(:Company)` relationships
  * 9. Connect `(:Company)-[:FILED]->(:Form)` relationships
  *
  * The resulting graph will look like this:
  *
  * @graph ```
  * (:Form => { 
  *     formId :: string!,   //  a unique identifier for the form
  *     source :: string!,   // a link back to the original 10k document
  *     summary :: string,   // text summary generated with the LLM **NOTE: not yet implemented! **
  *     summaryEmbeddings: list<float> // vector embedding of summary **NOTE: not yet implemented! **
  * })
  *
  * (:Chunk => {
  *    chunkId :: string!,  // a unique identifier for the chunk
  *    text :: string!,     // the text of the chunk 
  *    textEmbedding :: list<float> // vector embedding of the text
  * })
  * 
  * // @kind contains
  * // @synonyms 
  * (:Form)=[:SECTION => { item :: string }]=>(:Chunk)
  *
  * // @kind peer
  * // @antonym previous
  * (:Chunk)=[:NEXT^1]=>(:Chunk)
  *
  * // @kind membership
  * (:Chunk)=[:PART_OF^1]->(:Form)
  *
  * (:Company => {
  *     cik :: int!,            // the Central Index Key for the company
  *     cusip6:: string!,       // the CUSIP6 identifier for the company
  *     name :: string!,        // the name of the company
  *     names :: list<string>,  // list of alternative names for the company
  *     cusip:: list<string>,   // list of known CUSIP identifiers for the company
  *     address :: string       // the address of the company **NOTE: not yet implemented! **
  * })
  *
  * (:Manager {
  *     cik :: int!, // the Central Index Key for the manager
  *     name :: string, // the name of the manager
  *     address :: string // the address of the manager
  * })
  * 
  * (:Manager)=[:OWNS_STOCK_IN]=>(:Company)
  * (:Company)=[:FILED]=>(:Form)
  * ```
  *
  * @module LoadEdgarKG
  * @plugins apoc, genai
  * @param openAiApiKey::string - OpenAI API key
  * @param baseURL::string - Base URL for the data files
  */
MERGE (kg:KnowledgeGraph {name: "EdgarKG"})
  ON CREATE SET kg.createdAt = datetime()
  ON MATCH SET kg.lastOperation = datetime(),
              kg.sources = [$baseURL + 'form10k/*', $baseURL + 'form13.csv']
RETURN $moduleName as name // first statement in a module must RETURN module name
;
////////////////////////////////////////////////
// Load Form 10-K data

// create constraints
CREATE CONSTRAINT unique_form IF NOT EXISTS FOR (n:Form) REQUIRE n.formId IS UNIQUE
;
CREATE CONSTRAINT unique_chunk IF NOT EXISTS 
    FOR (c:Chunk) REQUIRE c.chunkId IS UNIQUE
;
// create vector index for form 10-K chunks
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
      section.text = apoc.any.property(f, item)
  MERGE (f)-[:SECTION {item: item}]->(section)
  MERGE (section)-[:PART_OF]->(f)
}
;
// Remove form section texts from the form nodes themselves
MATCH (f:Form)
SET f.item1 =  null, f.item1a = null, f.item7 = null, f.item7a = null
;
// Split the text into chunks of 1000 words
MATCH (f:Form)-[s:SECTION]->(first:Chunk)
WITH f, s, first
WITH f, s, first, apoc.text.split(first.text, "\s+") as tokens
CALL apoc.coll.partition(tokens, 1000) YIELD value
WITH f, s, first, apoc.text.join(value, " ") as chunk
WITH f, s, first, collect(chunk) as chunks
CALL {
    WITH f, s, first, chunks
    WITH f, s, first, chunks, [idx in range(1, size(chunks) -1) | 
         { chunkId: f.formId + "-" + s.item + "-chunk" + apoc.number.format(idx, "#0000"), text: chunks[idx] }] as chunkProps 
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
////////////////////////////////////////////////////////////////
// Load Form 13 data
CREATE CONSTRAINT unique_company 
    IF NOT EXISTS FOR (com:Company) 
    REQUIRE com.cusip6 IS UNIQUE
;
CREATE FULLTEXT INDEX fullTextCompanyNames
  IF NOT EXISTS
  FOR (com:Company) 
  ON EACH [com.names]
;
CREATE CONSTRAINT unique_manager 
  IF NOT EXISTS
  FOR (n:Manager) 
  REQUIRE n.cik IS UNIQUE
;
CREATE FULLTEXT INDEX fullTextManagerNames
  IF NOT EXISTS
  FOR (mgr:Manager) 
  ON EACH [mgr.name]
;
LOAD CSV WITH HEADERS FROM $baseURL + "form13.csv" as row
MERGE (com:Company {cusip6: row.cusip6})
  ON CREATE SET com.name = row.companyName,
                com.cusip = row.cusip
MERGE (mgr:Manager {cik: toInteger(row.managerCik)})
    ON CREATE SET mgr.name = row.managerName,
            mgr.address = row.managerAddress
MERGE (mgr)-[owns:OWNS_STOCK_IN { 
    reportCalendarOrQuarter: row.reportCalendarOrQuarter }]->(com)
    ON CREATE
      SET owns.value  = toFloat(row.value), 
          owns.shares = toInteger(row.shares)
;
// Connect the Form 10-K to the Company, migrating some properties from Form to Company
MATCH (com:Company), (form:Form)
  WHERE com.cusip6 = form.cusip6
SET com.names = form.names,
    com.cik = toInteger(form.cik)
SET form.names = null,
    form.cik = null,
    form.cusip6 = null,
    form.cusip = null
MERGE (com)-[:FILED]->(form)
;
// Generate embeddings for each chunk. This may take a while.
:auto  
MATCH (chunk:Chunk) WHERE chunk.textEmbedding IS NULL
CALL {
  WITH chunk
  WITH chunk, genai.vector.encode(chunk.text, "OpenAI", {token: $openAiApiKey}) AS vector
  CALL db.create.setNodeVectorProperty(chunk, "textEmbedding", vector)    
} IN TRANSACTIONS OF 10 ROWS
;
