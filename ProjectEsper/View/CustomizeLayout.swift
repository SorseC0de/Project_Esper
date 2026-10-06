import CoreGraphics

// Written by Tools/import_customize.py from Customize_Screen.svg; run it again rather than editing.

/// Where each of the customize screen's layers sits, as a share of the whole 16:9 screen
/// from its top left.
enum CustomizeLayout {
    static let aspect: CGFloat = 2560 / 1440
    static let frames: [String: CGRect] = [
        "customize_ground": CGRect(x: 0.02656, y: 0.03819, width: 0.94492, height: 0.89583),
        "customize_return": CGRect(x: 0.43477, y: 0.89444, width: 0.13164, height: 0.07431),
        "customize_start": CGRect(x: 0.41523, y: 0.35347, width: 0.16914, height: 0.30139),
        "customize_spin_ccw": CGRect(x: 0.42930, y: 0.38889, width: 0.13945, height: 0.23889),
        "customize_spin_cw": CGRect(x: 0.41016, y: 0.34514, width: 0.17656, height: 0.32014),
        "customize_p1_skin": CGRect(x: 0.29336, y: 0.15417, width: 0.05078, height: 0.08819),
        "customize_p1_skin_line": CGRect(x: 0.29297, y: 0.15347, width: 0.05156, height: 0.08889),
        "customize_p1_skin_lit": CGRect(x: 0.29180, y: 0.15139, width: 0.05391, height: 0.09306),
        "customize_p1_arms": CGRect(x: 0.29336, y: 0.33889, width: 0.05078, height: 0.08819),
        "customize_p1_arms_line": CGRect(x: 0.29297, y: 0.33819, width: 0.05195, height: 0.08958),
        "customize_p1_arms_lit": CGRect(x: 0.29219, y: 0.33611, width: 0.05352, height: 0.09375),
        "customize_p1_legs": CGRect(x: 0.29336, y: 0.52361, width: 0.05117, height: 0.08819),
        "customize_p1_legs_line": CGRect(x: 0.29336, y: 0.52292, width: 0.05156, height: 0.08958),
        "customize_p1_legs_lit": CGRect(x: 0.29219, y: 0.52153, width: 0.05391, height: 0.09306),
        "customize_p1_hood": CGRect(x: 0.34102, y: 0.65278, width: 0.06563, height: 0.11319),
        "customize_p1_hood_line": CGRect(x: 0.34063, y: 0.65139, width: 0.06680, height: 0.11528),
        "customize_p1_hood_lit": CGRect(x: 0.33945, y: 0.65000, width: 0.06875, height: 0.11875),
        "customize_p1_halo": CGRect(x: 0.02656, y: 0.20208, width: 0.34922, height: 0.51528),
        "customize_p1_display": CGRect(x: 0.10039, y: 0.73750, width: 0.20195, height: 0.13472),
        "customize_p1_display_bar": CGRect(x: 0.14453, y: 0.85833, width: 0.11445, height: 0.01736),
        "customize_p2_skin": CGRect(x: 0.65430, y: 0.15347, width: 0.05078, height: 0.08819),
        "customize_p2_skin_line": CGRect(x: 0.65391, y: 0.15278, width: 0.05195, height: 0.08958),
        "customize_p2_skin_lit": CGRect(x: 0.65312, y: 0.15069, width: 0.05352, height: 0.09375),
        "customize_p2_arms": CGRect(x: 0.65430, y: 0.33889, width: 0.05078, height: 0.08819),
        "customize_p2_arms_line": CGRect(x: 0.65391, y: 0.33819, width: 0.05195, height: 0.08958),
        "customize_p2_arms_lit": CGRect(x: 0.65312, y: 0.33611, width: 0.05352, height: 0.09306),
        "customize_p2_legs": CGRect(x: 0.65430, y: 0.52361, width: 0.05078, height: 0.08819),
        "customize_p2_legs_line": CGRect(x: 0.65391, y: 0.52292, width: 0.05195, height: 0.08958),
        "customize_p2_legs_lit": CGRect(x: 0.65312, y: 0.52153, width: 0.05352, height: 0.09306),
        "customize_p2_hood": CGRect(x: 0.59141, y: 0.65278, width: 0.06602, height: 0.11319),
        "customize_p2_hood_line": CGRect(x: 0.59102, y: 0.65139, width: 0.06680, height: 0.11528),
        "customize_p2_hood_lit": CGRect(x: 0.59023, y: 0.65000, width: 0.06875, height: 0.11875),
        "customize_p2_halo": CGRect(x: 0.62148, y: 0.20208, width: 0.34922, height: 0.51528),
        "customize_p2_display": CGRect(x: 0.69492, y: 0.73750, width: 0.20195, height: 0.13472),
        "customize_p2_display_bar": CGRect(x: 0.73906, y: 0.85833, width: 0.11445, height: 0.01736),
    ]
}
