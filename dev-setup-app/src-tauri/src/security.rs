// security.rs — Encryption and sanitization utilities for sensitive data
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use base64::{engine::general_purpose, Engine as _};
use sha2::{Digest, Sha256};

/// Encrypts sensitive data using AES-256-GCM
/// Returns base64-encoded ciphertext with prepended nonce (12 bytes)
pub fn encrypt_sensitive(plaintext: &str) -> Result<String, String> {
    if plaintext.is_empty() {
        return Ok(String::new());
    }
    
    // Use machine-specific key (derived from system identifiers)
    let key = derive_machine_key();
    let cipher = Aes256Gcm::new(&key);
    
    // Generate random nonce
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    
    // Encrypt
    let ciphertext = cipher
        .encrypt(&nonce, plaintext.as_bytes())
        .map_err(|e| format!("Encryption failed: {}", e))?;
    
    // Prepend nonce to ciphertext and base64 encode
    let mut result = nonce.to_vec();
    result.extend_from_slice(&ciphertext);
    
    Ok(general_purpose::STANDARD.encode(result))
}

/// Decrypts sensitive data encrypted with encrypt_sensitive()
pub fn decrypt_sensitive(encrypted: &str) -> Result<String, String> {
    if encrypted.is_empty() {
        return Ok(String::new());
    }
    
    // Decode base64
    let data = general_purpose::STANDARD
        .decode(encrypted)
        .map_err(|e| format!("Base64 decode failed: {}", e))?;
    
    if data.len() < 12 {
        return Err("Invalid encrypted data: too short".to_string());
    }
    
    // Extract nonce (12 bytes) and ciphertext
    let (nonce_bytes, ciphertext) = data.split_at(12);
    let nonce = Nonce::from_slice(nonce_bytes);
    
    // Decrypt
    let key = derive_machine_key();
    let cipher = Aes256Gcm::new(&key);
    
    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| format!("Decryption failed: {}", e))?;
    
    String::from_utf8(plaintext)
        .map_err(|e| format!("Invalid UTF-8: {}", e))
}

/// Derives a machine-specific encryption key using system identifiers
/// Uses SHA-256 hash of combined machine identifiers for 256-bit AES key
fn derive_machine_key() -> Key<Aes256Gcm> {
    use std::env;
    
    // Combine machine-specific identifiers
    // On Windows: COMPUTERNAME, USERNAME, PROCESSOR_IDENTIFIER
    // On Unix: HOSTNAME, USER, etc.
    let machine_id = format!(
        "{}_{}_{}_{}",
        env::var("COMPUTERNAME").or_else(|_| env::var("HOSTNAME")).unwrap_or_default(),
        env::var("USERNAME").or_else(|_| env::var("USER")).unwrap_or_default(),
        env::var("PROCESSOR_IDENTIFIER").unwrap_or_default(),
        env::var("PROCESSOR_REVISION").unwrap_or_default(),
    );
    
    // Hash to get 256-bit key
    let mut hasher = Sha256::new();
    hasher.update(machine_id.as_bytes());
    hasher.update(b"dev-setup-app-v2.4.0-salt");  // Application-specific salt
    let hash = hasher.finalize();
    
    *Key::<Aes256Gcm>::from_slice(&hash)
}

/// Redacts sensitive data patterns from log lines for safe display
/// Prevents credentials from appearing in logs
pub fn redact_sensitive_log(line: &str) -> String {
    let mut redacted = line.to_string();
    
    // Define sensitive patterns to redact
    let patterns = vec![
        // GitLab Personal Access Token
        (r"glpat-[a-zA-Z0-9_-]{20,}", "glpat-***REDACTED***"),
        // Generic tokens (20+ chars)
        (r"[Tt]oken[:\s=]+[a-zA-Z0-9_-]{20,}", "Token: ***REDACTED***"),
        // Passwords in environment/config
        (r"(PASSWORD|PASSWD|PWD)[:\s=]+\S+", "$1: ***REDACTED***"),
        // API keys
        (r"(API[_\s]?KEY|APIKEY)[:\s=]+\S+", "$1: ***REDACTED***"),
        // AWS Access Key ID
        (r"AKIA[0-9A-Z]{16}", "AKIA***REDACTED***"),
        // AWS Secret Access Key
        (r"aws_secret_access_key[:\s=]+\S+", "aws_secret_access_key: ***REDACTED***"),
        // Generic secrets
        (r"(SECRET|PRIVATE|CREDENTIAL)[:\s=]+\S+", "$1: ***REDACTED***"),
        // SETUP_GITLAB_PAT environment variable
        (r"SETUP_GITLAB_PAT[:\s=]+\S+", "SETUP_GITLAB_PAT: ***REDACTED***"),
        // GITLAB_PERSONAL_ACCESS_TOKEN
        (r"GITLAB_PERSONAL_ACCESS_TOKEN[:\s=]+\S+", "GITLAB_PERSONAL_ACCESS_TOKEN: ***REDACTED***"),
        // PRIVATE-TOKEN header
        (r"PRIVATE-TOKEN:\s*\S+", "PRIVATE-TOKEN: ***REDACTED***"),
        // Bearer tokens
        (r"Bearer\s+[a-zA-Z0-9_-]{20,}", "Bearer ***REDACTED***"),
    ];
    
    for (pattern, replacement) in patterns {
        if let Ok(re) = regex::Regex::new(pattern) {
            redacted = re.replace_all(&redacted, replacement).to_string();
        }
    }
    
    redacted
}

/// Generates a display-safe hash of sensitive data for logging
/// Returns first 8 characters of SHA-256 hash followed by "..."
/// Useful for debugging without exposing actual credentials
pub fn hash_for_display(sensitive: &str) -> String {
    if sensitive.is_empty() {
        return String::new();
    }
    
    let mut hasher = Sha256::new();
    hasher.update(sensitive.as_bytes());
    let hash = hasher.finalize();
    let hex_hash = hex::encode(hash);
    
    // Return first 8 chars + ellipsis
    format!("{}...", &hex_hash[..8])
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let plaintext = "glpat-secrettoken12345";
        let encrypted = encrypt_sensitive(plaintext).unwrap();
        
        // Encrypted should be different from plaintext
        assert_ne!(encrypted, plaintext);
        // Should be base64 (alphanumeric + =)
        assert!(encrypted.chars().all(|c| c.is_alphanumeric() || c == '=' || c == '+' || c == '/'));
        
        let decrypted = decrypt_sensitive(&encrypted).unwrap();
        assert_eq!(decrypted, plaintext);
    }
    
    #[test]
    fn test_encrypt_empty_string() {
        let encrypted = encrypt_sensitive("").unwrap();
        assert_eq!(encrypted, "");
        
        let decrypted = decrypt_sensitive("").unwrap();
        assert_eq!(decrypted, "");
    }
    
    #[test]
    fn test_redact_gitlab_pat() {
        let line = "Using GitLab PAT: glpat-abcd1234567890xyz";
        let redacted = redact_sensitive_log(line);
        assert!(!redacted.contains("glpat-abcd"));
        assert!(redacted.contains("***REDACTED***"));
    }
    
    #[test]
    fn test_redact_password_env() {
        let line = "export PASSWORD=mysecret123";
        let redacted = redact_sensitive_log(line);
        assert!(!redacted.contains("mysecret123"));
        assert!(redacted.contains("PASSWORD: ***REDACTED***"));
    }
    
    #[test]
    fn test_redact_aws_key() {
        let line = "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE";
        let redacted = redact_sensitive_log(line);
        assert!(!redacted.contains("AKIAIOSFODNN7EXAMPLE"));
        assert!(redacted.contains("AKIA***REDACTED***"));
    }
    
    #[test]
    fn test_redact_setup_gitlab_pat() {
        let line = "SETUP_GITLAB_PAT=glpat-1234567890abcdef";
        let redacted = redact_sensitive_log(line);
        assert!(!redacted.contains("glpat-1234567890"));
        assert!(redacted.contains("***REDACTED***"));
    }
    
    #[test]
    fn test_hash_for_display() {
        let hash = hash_for_display("glpat-secrettoken");
        assert_eq!(hash.len(), 11);  // 8 hex chars + "..."
        assert!(hash.ends_with("..."));
        
        // Same input should produce same hash
        let hash2 = hash_for_display("glpat-secrettoken");
        assert_eq!(hash, hash2);
        
        // Different input should produce different hash
        let hash3 = hash_for_display("different-token");
        assert_ne!(hash, hash3);
    }
    
    #[test]
    fn test_hash_empty_string() {
        let hash = hash_for_display("");
        assert_eq!(hash, "");
    }
}
