Arthas launcher binaries are downloaded on first use into the operator's local
`~/.performance-diagnosis/arthas/versions/4.3.5/` cache. The download script
records a local SHA-256 digest beside the JAR after verifying its embedded
version. This is a local integrity record for subsequent runs, not a publisher
signature. No binary or machine-specific digest is committed here.
