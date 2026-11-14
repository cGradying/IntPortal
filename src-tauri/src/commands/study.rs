use crate::*;

#[derive(Serialize)]
pub struct DeckSummary {
    id: String,
    name: String,
    subject: Option<String>,
    cards: usize,
    due: usize,
}

#[derive(Serialize)]
pub struct StudyOverview {
    decks: Vec<DeckSummary>,
    due: usize,
    streak: u32,
    reviews_today: u32,
    /// Reviews on each of the last seven days, oldest first (#239).
    week: [u32; 7],
}

/// Every deck with its due count, and the streak as of `today`.
#[tauri::command]
pub fn study(state: tauri::State<'_, AppState>, today: Date) -> Res<StudyOverview> {
    let store = state.store.lock().unwrap();
    let now = unix_now();
    let decks: Vec<DeckSummary> = store
        .decks()
        .map_err(err)?
        .into_iter()
        .map(|d| DeckSummary { due: d.due(now), cards: d.cards.len(), id: d.id, name: d.name, subject: d.subject })
        .collect();
    let stats = store.study_stats().map_err(err)?;
    let reviews_today = if stats.last_day == Some(today) { stats.reviews_today } else { 0 };
    Ok(StudyOverview { due: decks.iter().map(|d| d.due).sum(), decks, streak: study::current_streak(&stats, today), reviews_today, week: study::week(&stats, today) })
}

#[tauri::command]
pub fn deck(state: tauri::State<'_, AppState>, id: String) -> Res<Deck> {
    state.store.lock().unwrap().deck(&id).map_err(err)?.ok_or_else(|| "That deck is gone.".to_string())
}

/// Creates or replaces a deck; new cards (empty id) are numbered and due now.
#[tauri::command]
pub fn save_deck(state: tauri::State<'_, AppState>, mut deck: Deck) -> Res<Deck> {
    if deck.name.trim().is_empty() {
        return Err("Give the deck a name.".into());
    }
    deck.cards.retain(|c| !c.front.trim().is_empty() && !c.back.trim().is_empty());
    deck.settle_new_cards(unix_now());
    state.store.lock().unwrap().save_deck(&deck).map_err(err)?;
    Ok(deck)
}

#[tauri::command]
pub fn delete_deck(state: tauri::State<'_, AppState>, id: String) -> Res<()> {
    state.store.lock().unwrap().delete_deck(&id).map_err(err)
}

/// Pasted "front - back" lines as unsaved cards, for review before adding.
#[tauri::command]
pub fn parse_cards(text: String) -> Vec<Card> {
    study::parse_cards(&text)
        .into_iter()
        .map(|(front, back)| Card { id: String::new(), front, back, accepted: vec![], memory: Memory::new(0) })
        .collect()
}

#[derive(Serialize)]
pub struct Reviewed {
    deck: Deck,
    stats: Stats,
}

/// Rates one card, reschedules it and counts the review toward the streak.
#[tauri::command]
pub fn review_card(state: tauri::State<'_, AppState>, deck_id: String, card_id: String, rating: Rating, today: Date) -> Res<Reviewed> {
    let store = state.store.lock().unwrap();
    let mut deck = store.deck(&deck_id).map_err(err)?.ok_or("That deck is gone.")?;
    let card = deck.cards.iter_mut().find(|c| c.id == card_id).ok_or("That card is gone.")?;
    card.memory = study::review(&card.memory, rating, unix_now());
    let stats = study::count_review(&store.study_stats().map_err(err)?, today);
    store.save_deck(&deck).map_err(err)?;
    store.save_study_stats(&stats).map_err(err)?;
    Ok(Reviewed { deck, stats })
}

#[tauri::command]
pub fn check_answer(card: Card, typed: String) -> bool {
    study::is_correct(&typed, &card)
}

#[tauri::command]
pub fn distractors(cards: Vec<Card>, index: usize, seed: usize) -> Res<Vec<String>> {
    if index >= cards.len() {
        return Err("No such card.".into());
    }
    Ok(study::distractors(&cards, index, 3, seed))
}
