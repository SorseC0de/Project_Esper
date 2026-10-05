import CoreGraphics

// Written by Tools/import_customize.py from Customize_Screen.svg; run it again rather than editing.

/// Where each of the customize screen's layers sits, as a share of the whole 16:9 screen
/// from its top left.
enum CustomizeLayout {
    static let aspect: CGFloat = 2560 / 1440
    static let frames: [String: CGRect] = [
        "customize_ground": CGRect(x: 0.00000, y: 0.00000, width: 1.00000, height: 1.00000),
        "customize_return": CGRect(x: 0.43477, y: 0.89444, width: 0.13164, height: 0.07431),
        "customize_start": CGRect(x: 0.41523, y: 0.35347, width: 0.16914, height: 0.30139),
        "customize_spin_ccw": CGRect(x: 0.42930, y: 0.38889, width: 0.13945, height: 0.23889),
        "customize_spin_cw": CGRect(x: 0.41016, y: 0.34514, width: 0.17656, height: 0.32014),
        "customize_p1_skin": CGRect(x: 0.29297, y: 0.15347, width: 0.05156, height: 0.08889),
        "customize_p1_arms": CGRect(x: 0.29297, y: 0.33819, width: 0.05195, height: 0.08958),
        "customize_p1_legs": CGRect(x: 0.29336, y: 0.52292, width: 0.05156, height: 0.08958),
        "customize_p1_hood": CGRect(x: 0.34063, y: 0.65139, width: 0.06680, height: 0.11528),
        "customize_p1_halo": CGRect(x: 0.02656, y: 0.20208, width: 0.34922, height: 0.51528),
        "customize_p1_display": CGRect(x: 0.10039, y: 0.73750, width: 0.20195, height: 0.13819),
        "customize_p2_skin": CGRect(x: 0.65391, y: 0.15278, width: 0.05195, height: 0.08958),
        "customize_p2_arms": CGRect(x: 0.65391, y: 0.33819, width: 0.05195, height: 0.08958),
        "customize_p2_legs": CGRect(x: 0.65391, y: 0.52292, width: 0.05195, height: 0.08958),
        "customize_p2_hood": CGRect(x: 0.59102, y: 0.65139, width: 0.06680, height: 0.11528),
        "customize_p2_halo": CGRect(x: 0.62148, y: 0.20208, width: 0.34922, height: 0.51528),
        "customize_p2_display": CGRect(x: 0.69492, y: 0.73750, width: 0.20195, height: 0.13819),
    ]
}
