package hvrt

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/hex"
	"fmt"
	"hash"
	"io"
	"sort"
	"strings"

	"github.com/hvrt-vcs/hvrt/log"
	"golang.org/x/crypto/sha3"
)

// import (
// 	// "database/sql"
// 	// "os"
// 	// "path/filepath"
// 	// "github.com/klauspost/compress/zstd"
// 	// "database/sql"
// 	// "github.com/uptrace/bun/driver/sqliteshim"
// )

func init() {
}

type HashType string
type HashAlgorithm string

const (
	CHUNK_TYPE   HashType = "chunk"
	BLOB_TYPE    HashType = "blob"
	FILE_ID_TYPE HashType = "file_id"
	TREE_TYPE    HashType = "tree"
	COMMIT_TYPE  HashType = "commit"
	BUNDLE_TYPE  HashType = "bundle"
)

const (
	SHA3_256 HashAlgorithm = "sha3-256"
)

type hashCreator func() hash.Hash

var hashMapper = map[HashAlgorithm]hashCreator{
	"sha3-256": sha3.New256,
}

// Implements `hash.Hash` interface, but also returns the name of the algorithm
// used for the hash.
type NamedHash interface {
	hash.Hash
	Name() HashAlgorithm
}

type genericAlgorithm struct {
	internalName HashAlgorithm
	internalHash hash.Hash
}

func NewNamedHash(name HashAlgorithm) (NamedHash, error) {
	hashFunc, present := hashMapper[name]
	if !present {
		return nil, fmt.Errorf("%w: unknown hash algorithm '%v'", NotImplementedError, name)
	}

	return &genericAlgorithm{internalName: name, internalHash: hashFunc()}, nil
}

func (al *genericAlgorithm) Name() HashAlgorithm {
	return al.internalName
}

func (al *genericAlgorithm) Write(p []byte) (n int, err error) {
	return al.internalHash.Write(p)
}

func (al *genericAlgorithm) Sum(b []byte) []byte {
	return al.internalHash.Sum(b)
}

func (al *genericAlgorithm) Reset() {
	al.internalHash.Reset()
}

func (al *genericAlgorithm) Size() int {
	return al.internalHash.Size()
}

func (al *genericAlgorithm) BlockSize() int {
	return al.internalHash.BlockSize()
}

type Hashable interface {
	// bytes to pass to a hash.Hash instance
	HashBytes() []byte
}

const HashValueDelimiter = ":"

type HashValue struct {
	Type      HashType
	Algorithm HashAlgorithm
	HexDigest string
}

func (hv HashValue) ToStringSlice() []string {
	return []string{string(hv.Type), string(hv.Algorithm), hv.HexDigest}
}

func (hv HashValue) ToString() string {
	if hv.Type == "" || hv.Algorithm == "" || hv.HexDigest == "" {
		return ""
	} else {
		return strings.Join(hv.ToStringSlice(), HashValueDelimiter)
	}
}

func (hv HashValue) HashBytes() []byte {
	return []byte(hv.ToString())
}

type HashValueGenerator interface {
	GenerateHashValue() (HashValue, error)
}

func SliceContains[T comparable](slc []T, comp T) bool {
	for _, v := range slc {
		if v == comp {
			return true
		}
	}
	return false
}

func commitChunks(wt_tx, repo_tx *sql.Tx) error {
	// FIXME: do not hardcode this to sqlite
	var write_chunk_stmt *sql.Stmt
	write_chunk_path := "sql/sqlite/repo/commit/chunk.sql"
	if write_chunk_bytes, err := SQLFiles.ReadFile(write_chunk_path); err != nil {
		return err
	} else if write_chunk_stmt, err = repo_tx.Prepare(string(write_chunk_bytes)); err != nil {
		return err
	}
	defer write_chunk_stmt.Close()

	// Worktree is always sqlite
	var chunk_rows *sql.Rows
	read_chunks_path := "sql/sqlite/work_tree/read_chunks.sql"
	if read_chunks_bytes, err := SQLFiles.ReadFile(read_chunks_path); err != nil {
		return err
	} else if chunk_rows, err = wt_tx.Query(string(read_chunks_bytes)); err != nil {
		return err
	}
	defer chunk_rows.Close()

	var (
		hash             string
		hash_algo        string
		compression_algo string
		data             sql.RawBytes
	)

	for chunk_rows.Next() {
		if err := chunk_rows.Scan(&hash, &hash_algo, &compression_algo, &data); err != nil {
			return err
		}
		log.Debug.Printf("hash: '%v', hash_algo: '%v', compression_algo: '%v', data: '%v'", hash, hash_algo, compression_algo, data)

		if result, err := write_chunk_stmt.Exec(hash, hash_algo, compression_algo, data); err != nil {
			return err
		} else {
			log.Debug.Printf("execution result: %v", result)
		}
	}

	return nil
}

func commitBlobs(wt_tx, repo_tx *sql.Tx) error {
	// FIXME: do not hardcode this to sqlite
	var write_blob_stmt *sql.Stmt
	write_blob_path := "sql/sqlite/repo/commit/blob.sql"
	if write_blob_bytes, err := SQLFiles.ReadFile(write_blob_path); err != nil {
		return err
	} else if write_blob_stmt, err = repo_tx.Prepare(string(write_blob_bytes)); err != nil {
		return err
	}
	defer write_blob_stmt.Close()

	// Worktree is always sqlite
	var blob_rows *sql.Rows
	read_blobs_path := "sql/sqlite/work_tree/read_blobs.sql"
	if read_blobs_bytes, err := SQLFiles.ReadFile(read_blobs_path); err != nil {
		return err
	} else if blob_rows, err = wt_tx.Query(string(read_blobs_bytes)); err != nil {
		return err
	}
	defer blob_rows.Close()

	var (
		hash        string
		hash_algo   string
		byte_length int64
	)

	for blob_rows.Next() {
		if err := blob_rows.Scan(&hash, &hash_algo, &byte_length); err != nil {
			return err
		}
		log.Debug.Printf("hash: '%v', hash_algo: '%v', byte_length: '%v'", hash, hash_algo, byte_length)

		if result, err := write_blob_stmt.Exec(hash, hash_algo, byte_length); err != nil {
			return err
		} else {
			log.Debug.Printf("execution result: %v", result)
		}
	}

	return nil
}

func commitBlobChunks(wt_tx, repo_tx *sql.Tx) error {
	// FIXME: do not hardcode this to sqlite
	var write_blob_chunk_stmt *sql.Stmt
	write_blob_chunk_path := "sql/sqlite/repo/commit/blob_chunk.sql"
	if write_blob_chunk_bytes, err := SQLFiles.ReadFile(write_blob_chunk_path); err != nil {
		return err
	} else if write_blob_chunk_stmt, err = repo_tx.Prepare(string(write_blob_chunk_bytes)); err != nil {
		return err
	}
	defer write_blob_chunk_stmt.Close()

	// Worktree is always sqlite
	var blob_chunk_rows *sql.Rows
	read_chunks_path := "sql/sqlite/work_tree/read_blob_chunks.sql"
	if read_chunks_bytes, err := SQLFiles.ReadFile(read_chunks_path); err != nil {
		return err
	} else if blob_chunk_rows, err = wt_tx.Query(string(read_chunks_bytes)); err != nil {
		return err
	}
	defer blob_chunk_rows.Close()

	var (
		blob_hash       string
		blob_hash_algo  string
		chunk_hash      string
		chunk_hash_algo string
		start_byte      int64
		end_byte        int64
	)

	for blob_chunk_rows.Next() {
		if err := blob_chunk_rows.Scan(&blob_hash, &blob_hash_algo, &chunk_hash, &chunk_hash_algo, &start_byte, &end_byte); err != nil {
			return err
		}
		log.Debug.Printf(
			"blob_hash: '%v', blob_hash_algo: '%v', chunk_hash: '%v', chunk_hash_algo: '%v', start_byte: '%v', end_byte: '%v'",
			blob_hash, blob_hash_algo, chunk_hash, chunk_hash_algo, start_byte, end_byte,
		)

		if result, err := write_blob_chunk_stmt.Exec(blob_hash, blob_hash_algo, chunk_hash, chunk_hash_algo, start_byte, end_byte); err != nil {
			return err
		} else {
			log.Debug.Printf("execution result: %v", result)
		}
	}

	return nil
}

func CalculateFileID(path string, commit HashValue, parents []HashValue) (HashValue, error) {
	return HashValue{}, NotImplementedError
}

func CalculateBlob(blob io.Reader, hasher NamedHash) (HashValue, error) {
	if _, err := io.Copy(hasher, blob); err != nil {
		return HashValue{}, err
	}
	digest := hasher.Sum([]byte{})
	hex_digest := hex.EncodeToString(digest)
	return HashValue{Type: BLOB_TYPE, Algorithm: hasher.Name(), HexDigest: hex_digest}, nil
}

type TreeMember struct {
	Path   string
	FileId HashValue
	Blob   HashValue
}

func (t *TreeMember) HashBytes() []byte {
	string_slice := []string{
		t.Path,
		t.FileId.ToString(),
		t.Blob.ToString(),
	}
	joined_bytes := []byte(strings.Join(string_slice, "\t"))
	return joined_bytes
}

type Tree struct {
	Members []TreeMember
}

func (t *Tree) HashBytes() []byte {
	string_slice := make([]string, 0, len(t.Members))

	for _, tm := range t.Members {
		string_slice = append(string_slice, string(tm.HashBytes()))
	}
	sort.Strings(string_slice)
	joined_bytes := []byte(strings.Join(string_slice, "\n"))
	return joined_bytes
}

type HeaderMap map[string]string

func (hm HeaderMap) HashBytes() []byte {
	headers := make([]string, len(hm))

	sorted_keys := make([]string, len(hm))
	i := 0
	for k := range hm {
		sorted_keys[i] = k
		i++
	}
	sort.Strings(sorted_keys)

	for _, hk := range sorted_keys {
		headers = append(headers, fmt.Sprintf("%v=%v", hk, hm[hk]))
	}
	joined_bytes := []byte(strings.Join(headers, "\n"))
	return joined_bytes
}

type Commit struct {
	Headers HeaderMap
	Tree    Tree
}

func (c *Commit) HashBytes() []byte {
	child_byte_slices := [][]byte{
		c.Headers.HashBytes(),
		c.Tree.HashBytes(),
	}
	joined_bytes := bytes.Join(child_byte_slices, []byte("\n"))
	return joined_bytes
}

func commitTree(wt_tx, repo_tx *sql.Tx) (tree_hash string, tree_hash_algo string, err error) {
	head_commit_row := wt_tx.QueryRow(SQLStrings_sqlite_work_tree_read_head_commit)

	var (
		hash      string
		hash_algo string
	)

	if err := head_commit_row.Scan(&hash, &hash_algo); err != nil {
		return "", "", err
	}

	// treeMembers := make([]treeMember, 0)
	log.Debug.Printf("head commit hash '%v', hash_algo '%v'", hash, hash_algo)

	if hash != "0" && hash_algo != "nil" {
		// get previous commit tree and layer new changes on top of it
	} else {

	}

	return "", "", nil
}

func clearWorktreeDB(wt_tx, repo_tx *sql.Tx) error {
	// Worktree is always sqlite
	clear_path := "sql/sqlite/work_tree/clear.sql"
	if clear_bytes, err := SQLFiles.ReadFile(clear_path); err != nil {
		return err
	} else if result, err := wt_tx.Exec(string(clear_bytes)); err != nil {
		return err
	} else {
		log.Debug.Printf("clear result: '%v'", result)
		return nil
	}
}

// TODO: commit message, author, etc.
func finalCommit(tree_hash, tree_hash_algo, work_tree, message, author, committer string, wt_tx, repo_tx *sql.Tx) error {
	return nil
}

type simpleTransfer func(wt_tx, repo_tx *sql.Tx) error

func innerCommit(work_tree, message, author, committer string, wt_tx, repo_tx *sql.Tx) error {
	var (
		tree_hash      string
		tree_hash_algo string
	)

	commitTreeLocal := func(lwt_tx, lrepo_tx *sql.Tx) error {
		var lerr error
		if tree_hash, tree_hash_algo, lerr = commitTree(lwt_tx, lrepo_tx); lerr != nil {
			return lerr
		}
		return nil
	}

	funcs := []simpleTransfer{
		commitChunks,
		commitBlobs,
		commitBlobChunks,
		commitTreeLocal,
		clearWorktreeDB,
	}
	for _, f := range funcs {
		if err := f(wt_tx, repo_tx); err != nil {
			return err
		}
	}

	if err := finalCommit(tree_hash, tree_hash_algo, work_tree, message, author, committer, wt_tx, repo_tx); err != nil {
		return err
	}

	return nil
}

func CommitWorktree(work_tree, message, author, committer string) error {
	wt_db, err := GetExistingWorktreeDB(work_tree)
	if err != nil {
		return err
	}
	defer wt_db.Close()

	repo_db, err := GetExistingRepoDB(work_tree)
	if err != nil {
		return err
	}
	defer repo_db.Close()

	wt_tx, err := wt_db.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}

	repo_tx, err := repo_db.BeginTx(context.Background(), nil)
	if err != nil {
		if err := wt_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}
		return err
	}

	if err := innerCommit(work_tree, message, author, committer, wt_tx, repo_tx); err != nil {
		if err := wt_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}
		if err := repo_tx.Rollback(); err != nil {
			log.Error.Println(err)
		}

		return err
	} else {
		if err := wt_tx.Commit(); err != nil {
			if err := repo_tx.Rollback(); err != nil {
				log.Error.Println(err)
			}
			return err
		}
		if err := repo_tx.Commit(); err != nil {
			return err
		}
	}

	return nil
}
