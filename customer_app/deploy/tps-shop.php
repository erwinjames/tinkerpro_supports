<?php
/**
 * TinkerPro shop-info shim.
 *
 * Drop this file at the root of the POS box's local Apache (typically
 *   C:\xampp\htdocs\tps-shop.php
 * ).
 *
 * The customer_app on a sibling Windows machine on the shop wifi
 * scans LAN port 80 looking for a host that answers this URL with a
 * `shop_name` + `vat_reg` JSON pair — that's the POS server. We
 * deploy this PHP shim instead of having the Flutter app speak MySQL
 * directly because the Dart `mysql1` package has a known protocol
 * desync against MariaDB 10.4+ ("Got packets out of order"); PHP's
 * PDO connector doesn't have that issue.
 *
 * No authentication beyond the usual LAN-only assumption — the file
 * exposes ONLY shop_name (cosmetic) and vat_reg (boolean BIR flag),
 * which the customer can already see on every receipt the POS prints.
 * If you want to lock it down further, restrict the document root
 * directory in httpd.conf to private IP ranges.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-store');

try {
    // Defaults match the standard XAMPP / TinkerPro POS install:
    //   localhost MariaDB, root with no password, database `tinkerpro`.
    // Override via environment variables if your install differs.
    $host = getenv('TPS_DB_HOST') ?: '127.0.0.1';
    $port = (int) (getenv('TPS_DB_PORT') ?: 3306);
    $user = getenv('TPS_DB_USER') ?: 'root';
    $pass = getenv('TPS_DB_PASS');
    if ($pass === false) $pass = ''; // env unset is fine, "" is the default
    $db   = getenv('TPS_DB_NAME') ?: 'tinkerpro';

    $dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_TIMEOUT => 3,
    ]);

    $row = $pdo->query("SELECT shop_name, vat_reg FROM shop ORDER BY id ASC LIMIT 1")
               ->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        http_response_code(404);
        echo json_encode(['error' => 'shop table is empty']);
        exit;
    }

    echo json_encode([
        'shop_name' => (string) ($row['shop_name'] ?? ''),
        'vat_reg'   => (int)    ($row['vat_reg']   ?? 0),
        // Marker so the customer_app's discovery can distinguish a
        // valid POS shim from any other JSON-spitting service that
        // happens to live at /tps-shop.php on this LAN.
        'tps_shop'  => true,
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
