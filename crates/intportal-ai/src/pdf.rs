//! Text out of a PDF with lopdf, which returns errors instead of panicking
//! (the release build aborts on panic).
use lopdf::Document;

pub const MAX_BYTES: usize = 20 * 1024 * 1024;
pub const MAX_PAGES: usize = 300;

pub fn text(bytes: &[u8]) -> Result<String, String> {
    if bytes.len() > MAX_BYTES {
        return Err("This PDF is over 20 MB".into());
    }
    let doc = Document::load_mem(bytes).map_err(|_| "This file could not be read as a PDF".to_string())?;
    let pages: Vec<u32> = doc.get_pages().keys().copied().collect();
    if pages.len() > MAX_PAGES {
        return Err(format!("This PDF has {} pages; the limit is {MAX_PAGES}", pages.len()));
    }
    let mut out = String::new();
    for p in pages {
        if let Ok(t) = doc.extract_text(&[p]) {
            out.push_str(t.trim());
            out.push_str("\n\n");
        }
    }
    let out = out.trim().to_string();
    if out.is_empty() {
        return Err("This PDF has no text to read".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::{content::{Content, Operation}, dictionary, Object, Stream};

    fn pdf(text: Option<&str>) -> Vec<u8> {
        let mut doc = Document::with_version("1.5");
        let pages = doc.new_object_id();
        let font = doc.add_object(dictionary! {"Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica"});
        let res = doc.add_object(dictionary! {"Font" => dictionary! {"F1" => font}});
        let ops = match text {
            Some(t) => vec![
                Operation::new("BT", vec![]),
                Operation::new("Tf", vec!["F1".into(), 12.into()]),
                Operation::new("Td", vec![50.into(), 700.into()]),
                Operation::new("Tj", vec![Object::string_literal(t)]),
                Operation::new("ET", vec![]),
            ],
            None => vec![],
        };
        let content = doc.add_object(Stream::new(dictionary! {}, Content { operations: ops }.encode().unwrap()));
        let page = doc.add_object(dictionary! {"Type" => "Page", "Parent" => pages, "Contents" => content, "Resources" => res, "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()]});
        doc.objects.insert(pages, Object::Dictionary(dictionary! {"Type" => "Pages", "Kids" => vec![page.into()], "Count" => 1}));
        let catalog = doc.add_object(dictionary! {"Type" => "Catalog", "Pages" => pages});
        doc.trailer.set("Root", catalog);
        let mut buf = vec![];
        doc.save_to(&mut buf).unwrap();
        buf
    }

    #[test]
    fn reads_text_and_explains_a_scanned_or_broken_file() {
        assert_eq!(text(&pdf(Some("Week 1 Intro to Algorithms"))).unwrap(), "Week 1 Intro to Algorithms");
        assert_eq!(text(&pdf(None)), Err("This PDF has no text to read".into()));
        assert_eq!(text(b"not a pdf"), Err("This file could not be read as a PDF".into()));
        assert!(text(&vec![0; MAX_BYTES + 1]).unwrap_err().contains("20 MB"));
    }
}
