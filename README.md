# GraphRAG with SEC Edgar Knowledge Graph

Code and data for performing GraphRAG with an example SEC Edgar Knowledge Graph. The knowledge graph contains information about companies, their financial reports, and the relationships between them. 

<img width="934" alt="edgar-kg-model" src="https://github.com/neo4j-examples/sec-edgar-notebooks/assets/53756/58e3fcba-3def-459b-843b-c3403176b048">

## Knowledge Graph Model

From the Edgar database, two forms are used to construct a knowledge graph that mixes structured and unstructured data. The two forms are:

1. Form 10-K: the annual report that publicly traded companies must file with the SEC. It provides a comprehensive summary of a company's financial performance.
2. Form 13: filed by institutional managers who manage $100 million or more in assets.

### Form 13

Form 13 is used as structured data about the investments made by institutional managers. The form contains information about the companies in which the manager has invested, the number of shares owned, and the value of the investment.

```cypher
(:Manager)-[:OWNS_STOCK_IN]->(:Company)
```

### From 10-K

Form 10-K is used as a source of unstructured data about the company's financial performance. The form contains sections such as "Risk Factors", "Management's Discussion and Analysis of Financial Condition and Results of Operations", and "Financial Statements and Supplementary Data".

```cypher
(:Company)-[:FILED]->(:Form)
```

The form is divided into sections, and each section is split into chunks. The chunks contain the text of the form plus a vector embedding to enable vector similarity search.

```cypher
(:Form)-[:SECTION]->(:Chunk) // first chunk of a section
(:Chunk)-[:PART_OF]->(:Form) // each chunk connects back up to the form
(:Chunk)-[:NEXT]->(Chunk)    // the chunks are connected in a linked list
```

## Knowledge Graph Construction - quickstart

[kg-construction.cypher](notebooks/kg-construction/kg-construction.cypher) is a multi-statement Cypher script that constructs the knowledge graph. To create the knowledge graph, run the script in the Neo4j Browser.

1. Start a Neo4j database 
2. Set the OpenAI API Key at the top of the script
3. Run the script

*Note*: If you are using Neo4j Aura, the query interface does not support client-side commands in multi-statement scripts. So, you should first run the `:params` statement by itself to set query parameters. Then, run the rest of the script.

## Knowledge Graph Construction - step-by-step

To understand all the details about how the knowledge graph is constructed, follow the step-by-step guide in the [kg-construction](notebooks/kg-construction) directory.
