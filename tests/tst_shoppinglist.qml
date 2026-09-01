import QtQuick
import QtQuick.Controls
import QtTest
import "../shell/Shopping/ShoppingListEngine.js" as ShoppingListEngine

TestCase {
    name: "ShoppingListEngine"

    function test_empty_input() {
        compare(ShoppingListEngine.parse("   ,\n;  ").length, 0)
        compare(ShoppingListEngine.format([], "Einkauf"), "")
    }

    function test_mixed_input() {
        compare(
            ShoppingListEngine.parse("Milch, Brot\n6 Eier; Bananen"),
            ["Milch", "Brot", "6 Eier", "Bananen"]
        )
    }

    function test_free_text_connectors_and_bullets() {
        compare(
            ShoppingListEngine.parse("Ich brauche Milch und Brot, ☑ 6 Eier\n- grüne Äpfel"),
            ["Milch", "Brot", "6 Eier", "grüne Äpfel"]
        )
    }

    function test_unicode_format() {
        compare(
            ShoppingListEngine.format(["Äpfel", "Crème fraîche"], "Einkauf"),
            "🛒 *Einkauf*\n\n☐ Äpfel\n☐ Crème fraîche"
        )
    }
}
