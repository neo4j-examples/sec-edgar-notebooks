CREATE CONSTRAINT unique_form IF NOT EXISTS FOR (n:Form) REQUIRE n.formId IS UNIQUE
;
WITH 'https://raw.githubusercontent.com/neo4j-examples/sec-edgar-notebooks/main/data/sample/' as BASE_URL
LOAD CSV from BASE_URL + 'filenames.csv' AS row
RETURN row LIMIT 10