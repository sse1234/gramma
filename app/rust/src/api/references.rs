use gramma_core::reference::Reference;

/// Outcome of parsing user input as a Bible reference: exactly one of the two
/// fields is set.
pub struct ParseOutcome {
    pub osis: Option<String>,
    pub error: Option<String>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn parse_reference(input: String) -> ParseOutcome {
    match input.parse::<Reference>() {
        Ok(reference) => ParseOutcome {
            osis: Some(reference.to_string()),
            error: None,
        },
        Err(e) => ParseOutcome {
            osis: None,
            error: Some(e.to_string()),
        },
    }
}

/// Concise display form of a canonical OSIS reference ("1Mo 3,1"); falls
/// back to the input when it does not parse.
#[flutter_rust_bridge::frb(sync)]
pub fn format_reference(osis: String) -> String {
    osis.parse::<Reference>()
        .map(|r| r.display_concise())
        .unwrap_or(osis)
}

/// Canonical position of a book (0-based) for sorting annotation lists;
/// unknown books sort last.
#[flutter_rust_bridge::frb(sync)]
pub fn book_sort_index(osis: String) -> u32 {
    gramma_core::reference::book_by_osis(&osis)
        .map(|b| b.index() as u32)
        .unwrap_or(u32::MAX)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
