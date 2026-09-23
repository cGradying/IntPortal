/// The classic 4×4 ordered-dither threshold map (values 0 to 15), shared by
/// every dither in the app.
enum Bayer {
    static let matrix: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]
}
