// lib.rs
// Library module exposing IconResolver for benchmarking

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use rayon::prelude::*;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IconEntry {
    pub path: PathBuf,
    pub size: u32,
    pub is_svg: bool,
    pub theme_priority: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct CacheMetadata {
    // Cache format version - old caches without this field will deserialize as 0
    #[serde(default)]
    cache_version: u32,
    theme: String,
    base_path: PathBuf,
    additional_paths: Vec<PathBuf>,
    cache_time: u64,
    icon_count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct PersistentCache {
    metadata: CacheMetadata,
    icons: HashMap<String, IconEntry>,
}

pub struct IconResolver {
    pub cache: HashMap<String, IconEntry>,
    base_path: PathBuf,
    additional_paths: Vec<PathBuf>,
    theme: String,
    debug: bool,
}

impl IconResolver {
    // Current cache format version - increment when cache structure changes
    const CACHE_VERSION: u32 = 1;

    pub fn new() -> Self {
        let user = env::var("USER").unwrap_or_else(|_| "user".to_string());
        let theme = env::var("QT_ICON_THEME").unwrap_or_else(|_| "Papirus-Dark".to_string());
        let debug = env::var("RESOLVER_DEBUG").is_ok();
        
        let mut base_path = PathBuf::from(format!("/etc/profiles/per-user/{}/share/icons", user));
        
        if !base_path.exists() {
            if debug {
                eprintln!(
                    "[icon-resolver] Warning: Base path does not exist: {:?}. Trying fallback paths...",
                    base_path
                );
            }
            
            let fallback_paths = vec![
                dirs::home_dir()
                    .map(|h| h.join(".nix-profile").join("share").join("icons"))
                    .unwrap_or_else(|| PathBuf::from("")),
                PathBuf::from("/run/current-system/sw/share/icons"),
                PathBuf::from("/usr/share/icons"),
            ];
            
            let mut found_path = false;
            for fallback in fallback_paths {
                if !fallback.as_os_str().is_empty() && fallback.exists() {
                    base_path = fallback;
                    found_path = true;
                    if debug {
                        eprintln!("[icon-resolver] Using fallback path: {:?}", base_path);
                    }
                    break;
                }
            }
            
            if !found_path {
                eprintln!(
                    "[icon-resolver] Error: No valid icon directory found. Using default: /usr/share/icons"
                );
                base_path = PathBuf::from("/usr/share/icons");
            }
        }

        let mut additional_paths = Vec::new();
        if let Ok(xdg_data_dirs) = env::var("XDG_DATA_DIRS") {
            for path_str in xdg_data_dirs.split(':') {
                let path = PathBuf::from(path_str.trim()).join("icons");
                if path.exists() {
                    if debug {
                        eprintln!("[icon-resolver] Added XDG_DATA_DIRS path: {:?}", path);
                    }
                    additional_paths.push(path);
                }
            }
        }

        let mut resolver = Self {
            cache: HashMap::new(),
            base_path: base_path.clone(),
            additional_paths: additional_paths.clone(),
            theme: theme.clone(),
            debug,
        };

        // Try to load cache from disk first
        if let Some(cache_path) = resolver.get_cache_path() {
            if let Ok(loaded_cache) = resolver.load_cache_from_disk(&cache_path) {
                if resolver.is_cache_valid(&loaded_cache.metadata, &base_path, &additional_paths, &theme) {
                    if debug {
                        eprintln!("[icon-resolver] Loaded cache from disk: {} icons", loaded_cache.icons.len());
                    }
                    resolver.cache = loaded_cache.icons;
                    return resolver;
                } else if debug {
                    eprintln!("[icon-resolver] Cache is stale, rebuilding...");
                }
            }
        }

        // Cache not available or invalid, build it
        resolver.build_cache();
        
        // Save cache to disk
        if let Some(cache_path) = resolver.get_cache_path() {
            if let Err(e) = resolver.save_cache_to_disk(&cache_path) {
                if debug {
                    eprintln!("[icon-resolver] Failed to save cache: {}", e);
                }
            }
        }

        resolver
    }

    fn get_cache_path(&self) -> Option<PathBuf> {
        // Use XDG cache directory: ~/.cache/noctalia/icon-cache.json
        if let Some(cache_dir) = dirs::cache_dir() {
            let cache_file = cache_dir.join("noctalia").join("icon-cache.json");
            // Ensure directory exists
            if let Some(parent) = cache_file.parent() {
                let _ = fs::create_dir_all(parent);
            }
            Some(cache_file)
        } else {
            None
        }
    }

    fn load_cache_from_disk(&self, cache_path: &PathBuf) -> Result<PersistentCache, Box<dyn std::error::Error>> {
        let content = fs::read_to_string(cache_path)?;
        let cache: PersistentCache = serde_json::from_str(&content)?;
        Ok(cache)
    }

    fn save_cache_to_disk(&self, cache_path: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
        let cache_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let cache = PersistentCache {
            metadata: CacheMetadata {
                cache_version: Self::CACHE_VERSION,
                theme: self.theme.clone(),
                base_path: self.base_path.clone(),
                additional_paths: self.additional_paths.clone(),
                cache_time,
                icon_count: self.cache.len(),
            },
            icons: self.cache.clone(),
        };

        let json = serde_json::to_string_pretty(&cache)?;
        
        // Atomic write: write to temp file, then rename
        // This prevents corruption if the process is killed mid-write
        let temp_path = cache_path.with_extension("json.tmp");
        fs::write(&temp_path, json)?;
        fs::rename(&temp_path, cache_path)?;
        
        Ok(())
    }

    fn is_cache_valid(
        &self,
        metadata: &CacheMetadata,
        current_base_path: &PathBuf,
        current_additional_paths: &[PathBuf],
        current_theme: &str,
    ) -> bool {
        // Check cache version - reject old cache formats
        // Old caches without cache_version will deserialize as 0 (default)
        if metadata.cache_version != Self::CACHE_VERSION {
            return false;
        }

        // Check if theme changed
        if metadata.theme != *current_theme {
            return false;
        }

        // Check if base path changed
        if metadata.base_path != *current_base_path {
            return false;
        }

        // Check if additional paths changed
        if metadata.additional_paths.len() != current_additional_paths.len() {
            return false;
        }
        for (a, b) in metadata.additional_paths.iter().zip(current_additional_paths.iter()) {
            if a != b {
                return false;
            }
        }

        // Check if theme directory was modified (simple check: index.theme modification time)
        let theme_path = current_base_path.join(&metadata.theme).join("index.theme");
        if let Ok(theme_meta) = fs::metadata(&theme_path) {
            if let Ok(theme_mtime) = theme_meta.modified() {
                if let Ok(theme_duration) = theme_mtime.duration_since(UNIX_EPOCH) {
                    let theme_secs = theme_duration.as_secs();
                    if theme_secs > metadata.cache_time {
                        // Theme was modified after cache was created
                        return false;
                    }
                }
            }
        }

        true
    }

    pub fn build_cache(&mut self) {
        self.cache.clear();
        if self.debug {
            eprintln!("[icon-resolver] Building icon cache for theme: {}", self.theme);
        }

        let mut themes = Vec::new();
        let mut all_base_paths = vec![self.base_path.clone()];
        all_base_paths.extend(self.additional_paths.clone());
        
        self.collect_theme_chain(&self.theme, &mut themes, &self.base_path, &all_base_paths);

        if !themes.contains(&"hicolor".to_string()) {
            themes.push("hicolor".to_string());
            if self.debug {
                eprintln!("[icon-resolver] Added hicolor as guaranteed fallback");
            }
        }

        let base_path = self.base_path.clone();
        for (priority, theme) in themes.iter().enumerate() {
            self.scan_theme(theme, &base_path, priority);
        }

        let additional_paths = self.additional_paths.clone();
        let base_priority = themes.len();
        for additional_path in &additional_paths {
            for (priority, theme) in themes.iter().enumerate() {
                self.scan_theme(theme, additional_path, base_priority + priority);
            }
        }

        if self.debug {
            eprintln!("[icon-resolver] Cache built with {} icons", self.cache.len());
        }

        // Save cache to disk after building
        if let Some(cache_path) = self.get_cache_path() {
            if let Err(e) = self.save_cache_to_disk(&cache_path) {
                if self.debug {
                    eprintln!("[icon-resolver] Failed to save cache: {}", e);
                }
            }
        }
    }

    fn collect_theme_chain(&self, theme: &str, themes: &mut Vec<String>, primary_base: &PathBuf, all_bases: &[PathBuf]) {
        if themes.contains(&theme.to_string()) {
            return;
        }
        themes.push(theme.to_string());

        let mut found_index = false;
        for base in all_bases {
            let index_path = base.join(theme).join("index.theme");
            if let Ok(content) = fs::read_to_string(&index_path) {
                found_index = true;
                let mut in_icon_theme_section = false;
                for line in content.lines() {
                    let line = line.trim();
                    
                    if line.starts_with('[') && line.ends_with(']') {
                        in_icon_theme_section = line == "[Icon Theme]";
                        continue;
                    }
                    
                    if in_icon_theme_section && line.starts_with("Inherits=") {
                        if let Some(inherits_str) = line.split('=').nth(1) {
                            for inherited_theme in inherits_str.split(',') {
                                let inherited_theme = inherited_theme.trim();
                                if !inherited_theme.is_empty() {
                                    self.collect_theme_chain(inherited_theme, themes, primary_base, all_bases);
                                }
                            }
                        }
                    }
                }
                break;
            }
        }
        
        if !found_index && self.debug {
            eprintln!("[icon-resolver] Warning: Could not find index.theme for theme '{}' in any base path", theme);
        }
    }

    fn scan_theme(&mut self, theme: &str, base_path: &PathBuf, theme_priority: usize) {
        let theme_path = base_path.join(theme);
        if !theme_path.exists() {
            return;
        }

        let mut directories = self.get_theme_directories(&theme_path);
        
        if directories.is_empty() {
            if self.debug {
                eprintln!("[icon-resolver] No directories found in index.theme for {}, using fallback sizes", theme);
            }
            directories = vec![
                ("48x48".to_string(), 48),
                ("64x64".to_string(), 64),
                ("32x32".to_string(), 32),
                ("24x24".to_string(), 24),
                ("22x22".to_string(), 22),
                ("16x16".to_string(), 16),
                ("scalable".to_string(), 0),
            ];
        }

        let subdirectories = vec!["apps", "actions", "devices", "places", "status", "mimetypes", "categories"];

        // Collect all directories to scan (no I/O yet)
        let mut scan_tasks = Vec::new();
        for (size_str, size_val) in directories {
            for subdir in &subdirectories {
                let icon_path = if size_str.contains('/') {
                    theme_path.join(&size_str)
                } else {
                    theme_path.join(&size_str).join(subdir)
                };
                
                if icon_path.exists() {
                    for ext in &["svg", "png"] {
                        scan_tasks.push((icon_path.clone(), *ext, size_val, theme_priority));
                    }
                }
            }
        }

        // Parallelize directory scanning
        let scanned_icons: Vec<(String, IconEntry)> = scan_tasks
            .par_iter()
            .flat_map(|(icon_path, ext, size_val, theme_priority)| {
                let mut results = Vec::new();
                
                if let Ok(entries) = fs::read_dir(icon_path) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if let Some(file_ext) = path.extension() {
                            if file_ext.to_string_lossy().to_lowercase() == *ext {
                                if let Some(stem) = path.file_stem() {
                                    let icon_name = stem.to_string_lossy().to_string();
                                    let is_svg = *ext == "svg";
                                    
                                    results.push((
                                        icon_name,
                                        IconEntry {
                                            path: path.clone(),
                                            size: *size_val,
                                            is_svg,
                                            theme_priority: *theme_priority,
                                        },
                                    ));
                                }
                            }
                        }
                    }
                }
                
                results
            })
            .collect();

        // Merge results sequentially (preserves priority ordering)
        for (icon_name, entry) in scanned_icons {
            let should_add = match self.cache.get(&icon_name) {
                None => true,
                Some(existing) => {
                    if entry.theme_priority < existing.theme_priority {
                        true
                    } else if entry.theme_priority > existing.theme_priority {
                        false
                    } else {
                        if entry.is_svg && !existing.is_svg {
                            true
                        } else if entry.is_svg == existing.is_svg {
                            if entry.is_svg {
                                if existing.size == 0 && entry.size > 0 {
                                    true
                                } else if entry.size == 0 && existing.size > 0 {
                                    false
                                } else {
                                    entry.size > existing.size
                                }
                            } else {
                                entry.size > existing.size
                            }
                        } else {
                            false
                        }
                    }
                }
            };

            if should_add {
                self.cache.insert(icon_name, entry);
            }
        }
    }

    fn get_theme_directories(&self, theme_path: &PathBuf) -> Vec<(String, u32)> {
        let index_path = theme_path.join("index.theme");
        let mut directories = Vec::new();
        let mut in_icon_theme_section = false;
        let mut directory_names = Vec::new();
        let mut directory_sizes: HashMap<String, u32> = HashMap::new();
        let mut current_section = String::new();

        if let Ok(content) = fs::read_to_string(&index_path) {
            for line in content.lines() {
                let line = line.trim();
                
                if line.starts_with('[') && line.ends_with(']') {
                    in_icon_theme_section = line == "[Icon Theme]";
                    current_section = line[1..line.len()-1].to_string();
                    continue;
                }

                if in_icon_theme_section && line.starts_with("Directories=") {
                    if let Some(dirs_str) = line.split('=').nth(1) {
                        for dir_name in dirs_str.split(',') {
                            let dir_name = dir_name.trim().to_string();
                            if !dir_name.is_empty() {
                                directory_names.push(dir_name);
                            }
                        }
                    }
                }

                if !current_section.is_empty() && line.starts_with("Size=") {
                    if let Ok(size_val) = line.split('=').nth(1).unwrap_or("").trim().parse::<u32>() {
                        directory_sizes.insert(current_section.clone(), size_val);
                    }
                }
            }

            for dir_name_full in directory_names {
                let size = if let Some(&explicit_size) = directory_sizes.get(&dir_name_full) {
                    explicit_size
                } else {
                    let size_part = if let Some(slash_pos) = dir_name_full.find('/') {
                        &dir_name_full[..slash_pos]
                    } else {
                        &dir_name_full
                    };

                    if size_part == "scalable" {
                        0
                    } else if let Some(x_pos) = size_part.find('x') {
                        if let Ok(size_val) = size_part[..x_pos].parse::<u32>() {
                            size_val
                        } else {
                            continue;
                        }
                    } else {
                        continue;
                    }
                };

                directories.push((dir_name_full, size));
            }
        }

        directories.sort_by(|a, b| {
            match (a.1 == 0, b.1 == 0) {
                (true, true) => std::cmp::Ordering::Equal,
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                (false, false) => b.1.cmp(&a.1),
            }
        });
        directories
    }

    pub fn try_variations(&self, name: &str) -> Option<String> {
        let variation = format!("{}-browser", name);
        if self.cache.contains_key(&variation) {
            return Some(variation);
        }

        let variation = format!("{}-client", name);
        if self.cache.contains_key(&variation) {
            return Some(variation);
        }

        let prefixes = vec!["preferences-", "utilities-", "accessories-"];
        for prefix in &prefixes {
            let variation = format!("{}{}", prefix, name);
            if self.cache.contains_key(&variation) {
                return Some(variation);
            }
        }

        let variation = name.to_lowercase();
        if variation != name && self.cache.contains_key(&variation) {
            return Some(variation);
        }

        if name.contains('.') {
            if let Some(reverse_domain) = name.split('.').last() {
                if reverse_domain != name && self.cache.contains_key(reverse_domain) {
                    return Some(reverse_domain.to_string());
                }
                let reverse_domain_lower = reverse_domain.to_lowercase();
                if reverse_domain_lower != name && self.cache.contains_key(&reverse_domain_lower) {
                    return Some(reverse_domain_lower);
                }
            }
        }

        if name.contains(' ') {
            let variation = name.to_lowercase().replace(' ', "-");
            if variation != name && self.cache.contains_key(&variation) {
                return Some(variation);
            }
        }

        if name.contains('-') {
            let variation = name.replace('-', "_");
            if self.cache.contains_key(&variation) {
                return Some(variation);
            }
            let variation_lower = name.to_lowercase().replace('-', "_");
            if variation_lower != name && self.cache.contains_key(&variation_lower) {
                return Some(variation_lower);
            }
        }

        if name.contains('_') {
            let variation = name.replace('_', "-");
            if self.cache.contains_key(&variation) {
                return Some(variation);
            }
            let variation_lower = name.to_lowercase().replace('_', "-");
            if variation_lower != name && self.cache.contains_key(&variation_lower) {
                return Some(variation_lower);
            }
        }

        if !name.is_empty() {
            let mut chars = name.chars();
            if let Some(first_char) = chars.next() {
                let capitalized = first_char.to_uppercase().collect::<String>() + &chars.as_str();
                let variation = format!("org.{}.{}", name, capitalized);
                if self.cache.contains_key(&variation) {
                    return Some(variation);
                }

                let variation = format!("org.{}.{}", name, name);
                if self.cache.contains_key(&variation) {
                    return Some(variation);
                }

                let variation = format!("org.{}", name);
                if self.cache.contains_key(&variation) {
                    return Some(variation);
                }
            }
        }

        None
    }

    pub fn resolve(&self, name: &str) -> String {
        // Handle absolute file paths as a special case
        if name.starts_with('/') {
            let path = std::path::Path::new(name);
            if path.exists() && path.is_file() {
                // Return absolute path as-is if file exists
                return name.to_string();
            } else {
                // File doesn't exist, return empty string (fallback handled by caller)
                if self.debug {
                    eprintln!("[icon-resolver] Absolute path does not exist: {}", name);
                }
                return String::new();
            }
        }
        
        // Preprocess: Strip version numbers and metadata from window classes
        // This is defense-in-depth in case QML layer doesn't catch all cases
        if name.contains(' ') || name.contains('*') || name.contains('-') || name.contains('_') {
            // Split on common delimiters and try the first part (base application name)
            let parts: Vec<&str> = name.split(&[' ', '*', '-', '_'][..])
                .filter(|s| !s.is_empty())
                .collect();
            
            if !parts.is_empty() {
                let first_part = parts[0];
                
                // Try resolving the base name first (before version numbers)
                if let Some(entry) = self.cache.get(first_part) {
                    return entry.path.to_string_lossy().to_string();
                }
                
                // Also try lowercase version
                let first_part_lower = first_part.to_lowercase();
                if let Some(entry) = self.cache.get(&first_part_lower) {
                    return entry.path.to_string_lossy().to_string();
                }
                
                // Try variations on the base name
                if let Some(variation) = self.try_variations(first_part) {
                    if let Some(entry) = self.cache.get(&variation) {
                        return entry.path.to_string_lossy().to_string();
                    }
                }
                
                // Try variations on lowercase base name
                if let Some(variation) = self.try_variations(&first_part_lower) {
                    if let Some(entry) = self.cache.get(&variation) {
                        return entry.path.to_string_lossy().to_string();
                    }
                }
            }
        }
        
        // Continue with normal icon theme resolution for non-absolute paths
        let mut best_entry: Option<&IconEntry> = None;
        
        if let Some(entry) = self.cache.get(name) {
            best_entry = Some(entry);
        }
        
        if let Some(variation) = self.try_variations(name) {
            if let Some(entry) = self.cache.get(&variation) {
                let is_better = match best_entry {
                    None => true,
                    Some(best) => {
                        if entry.theme_priority < best.theme_priority {
                            true
                        } else if entry.theme_priority > best.theme_priority {
                            false
                        } else {
                            if entry.is_svg && !best.is_svg {
                                true
                            } else if entry.is_svg == best.is_svg {
                                if entry.is_svg {
                                    if best.size == 0 && entry.size > 0 {
                                        true
                                    } else if entry.size == 0 && best.size > 0 {
                                        false
                                    } else {
                                        entry.size > best.size
                                    }
                                } else {
                                    entry.size > best.size
                                }
                            } else {
                                false
                            }
                        }
                    }
                };
                
                if is_better {
                    best_entry = Some(entry);
                }
            }
        }
        
        if let Some(entry) = best_entry {
            return entry.path.to_string_lossy().to_string();
        }

        String::new()
    }

    pub fn reload(&mut self) -> usize {
        self.build_cache();
        
        // Save cache to disk after reload
        if let Some(cache_path) = self.get_cache_path() {
            if let Err(e) = self.save_cache_to_disk(&cache_path) {
                if self.debug {
                    eprintln!("[icon-resolver] Failed to save cache after reload: {}", e);
                }
            }
        }
        
        self.cache.len()
    }

    pub fn search(&self, pattern: &str) -> Vec<String> {
        let pattern_lower = pattern.to_lowercase();
        let mut matches: Vec<String> = self
            .cache
            .keys()
            .filter(|icon_name| icon_name.to_lowercase().contains(&pattern_lower))
            .cloned()
            .collect();
        
        matches.sort();
        matches
    }
}

