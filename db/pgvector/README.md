## Usage

https://github.com/pgvector/pgvector

Enable the extension (do this once in each database where you want to use it)

```sql
CREATE EXTENSION vector;
```

Create a vector column with 3 dimensions

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
```

Insert vectors

```sql
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
```

Get the nearest neighbors by L2 distance

```sql
SELECT \* FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

Also supports inner product (<#>), cosine distance (<=>), and L1 distance (<+>)

Note: <#> returns the negative inner product since Postgres only supports ASC order index scans on operators

Storing
Create a new table with a vector column

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
```

Or add a vector column to an existing table

```sql
ALTER TABLE items ADD COLUMN embedding vector(3);
```

Also supports half-precision, binary, and sparse vectors

Insert vectors

```sql
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
```

Or load vectors in bulk using COPY (example)

```sql
COPY items (embedding) FROM STDIN WITH (FORMAT BINARY);
```

Upsert vectors

```sql
INSERT INTO items (id, embedding) VALUES (1, '[1,2,3]'), (2, '[4,5,6]')
ON CONFLICT (id) DO UPDATE SET embedding = EXCLUDED.embedding;
```

Update vectors

```sql
UPDATE items SET embedding = '[1,2,3]' WHERE id = 1;
```

Delete vectors

```sql
DELETE FROM items WHERE id = 1;
```

Querying
Get the nearest neighbors to a vector

```sql
SELECT \* FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

Supported distance functions are:

<-> - L2 distance
<#> - (negative) inner product
<=> - cosine distance
<+> - L1 distance
<~> - Hamming distance (binary vectors)
<%> - Jaccard distance (binary vectors)
Get the nearest neighbors to a row

```sql
SELECT \* FROM items WHERE id != 1 ORDER BY embedding <-> (SELECT embedding FROM items WHERE id = 1) LIMIT 5;
```

Get rows within a certain distance

```sql
SELECT \* FROM items WHERE embedding <-> '[3,1,2]' < 5;
```

Note: Combine with ORDER BY and LIMIT to use an index

Distances
Get the distance

```sql
SELECT embedding <-> '[3,1,2]' AS distance FROM items;
```

For inner product, multiply by -1 (since <#> returns the negative inner product)

```sql
SELECT (embedding <#> '[3,1,2]') \* -1 AS inner_product FROM items;
```

For cosine similarity, use 1 - cosine distance

```sql
SELECT 1 - (embedding <=> '[3,1,2]') AS cosine_similarity FROM items;
```

Aggregates
Average vectors

```sql
SELECT AVG(embedding) FROM items;
```

Average groups of vectors

```sql
SELECT category_id, AVG(embedding) FROM items GROUP BY category_id;
```
