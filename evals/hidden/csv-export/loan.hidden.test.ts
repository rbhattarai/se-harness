// Hidden acceptance tests for REQ-001 (loan-webapp). Implementation-agnostic: they only
// drive the exported Express app with the data store mocked, exactly like the repo's own tests.
import { describe, it, expect, vi, beforeEach } from "vitest";
import request from "supertest";

vi.mock("../src/data/loanStore", () => ({
    readLoans: vi.fn(),
    writeLoan: vi.fn(),
    deleteLoan: vi.fn(),
    generateLoanId: vi.fn(),
}));
vi.mock("../src/events", () => ({
    addClient: vi.fn(),
    broadcast: vi.fn(),
    notifyApp: vi.fn(),
}));

import app from "../src/app";
import { readLoans } from "../src/data/loanStore";

const HEADER = "id,applicantName,amount,status,approver,createdAt";

// Minimal RFC 4180 parser so assertions don't depend on the implementation's line endings.
function parseCsv(text: string): string[][] {
    const rows: string[][] = [];
    let row: string[] = [];
    let field = "";
    let q = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (q) {
            if (ch === '"' && text[i + 1] === '"') {
                field += '"';
                i++;
            } else if (ch === '"') q = false;
            else field += ch;
        } else if (ch === '"') q = true;
        else if (ch === ",") {
            row.push(field);
            field = "";
        } else if (ch === "\n" || ch === "\r") {
            if (ch === "\r" && text[i + 1] === "\n") i++;
            row.push(field);
            rows.push(row);
            row = [];
            field = "";
        } else field += ch;
    }
    if (field !== "" || row.length) {
        row.push(field);
        rows.push(row);
    }
    return rows;
}

const asText = (
    r: NodeJS.ReadableStream,
    cb: (err: Error | null, body: string) => void,
) => {
    let d = "";
    r.on("data", (c: Buffer) => (d += c.toString("utf8")));
    r.on("end", () => cb(null, d));
};

const LOANS = [
    {
        id: "LOAN-20260101-AAAA",
        applicantName: "Jane Smith",
        amount: 25000,
        status: "New" as const,
        approver: "",
        createdAt: "2026-01-01T10:00:00.000Z",
    },
    {
        id: "LOAN-20260102-BBBB",
        applicantName: 'Smith, "Jr"\nSecond line',
        amount: 1250.5,
        status: "Approved" as const,
        approver: "John Doe",
        createdAt: "2026-01-02T11:30:00.000Z",
    },
];

describe("hidden: GET /loan/export.csv", () => {
    beforeEach(() => {
        vi.resetAllMocks();
    });

    it("AC1 returns 200, text/csv and an attachment filename with a date", async () => {
        vi.mocked(readLoans).mockReturnValue(LOANS);
        const res = await request(app).get("/loan/export.csv");
        expect(res.status).toBe(200);
        expect(res.headers["content-type"]).toMatch(/^text\/csv/);
        expect(res.headers["content-disposition"]).toMatch(
            /^attachment; filename="loans-\d{4}-\d{2}-\d{2}\.csv"$/,
        );
    });

    it("AC2 exact header row, one record per loan, in readLoans() order, raw values", async () => {
        vi.mocked(readLoans).mockReturnValue(LOANS);
        const res = await request(app).get("/loan/export.csv").buffer(true).parse(asText);
        const rows = parseCsv(String(res.body));
        expect(rows[0].join(",")).toBe(HEADER);
        expect(rows).toHaveLength(1 + LOANS.length);
        expect(rows[1]).toEqual([
            "LOAN-20260101-AAAA",
            "Jane Smith",
            "25000",
            "New",
            "",
            "2026-01-01T10:00:00.000Z",
        ]);
        expect(rows[2][2]).toBe("1250.5"); // plain number, not "$1,250.50"
        expect(rows[2][5]).toBe("2026-01-02T11:30:00.000Z"); // ISO 8601, not locale-formatted
    });

    it("AC5 quotes fields containing comma, quote or newline and doubles inner quotes", async () => {
        vi.mocked(readLoans).mockReturnValue(LOANS);
        const res = await request(app).get("/loan/export.csv").buffer(true).parse(asText);
        const body = String(res.body);
        expect(body).toContain('"Smith, ""Jr""\nSecond line"');
        expect(parseCsv(body)[2][1]).toBe('Smith, "Jr"\nSecond line');
    });

    it("AC5 each special character on its own triggers quoting", async () => {
        const mk = (name: string) => ({ ...LOANS[0], applicantName: name });
        vi.mocked(readLoans).mockReturnValue([mk("a,b"), mk('a"b'), mk("a\nb"), mk("plain")]);
        const res = await request(app).get("/loan/export.csv").buffer(true).parse(asText);
        const body = String(res.body);
        expect(body).toContain(',"a,b",');
        expect(body).toContain(',"a""b",');
        expect(body).toContain(',"a\nb",');
        expect(body).toContain(",plain,"); // and ordinary values stay unquoted
    });

    it("AC6 empty store -> 200 with only the header row", async () => {
        vi.mocked(readLoans).mockReturnValue([]);
        const res = await request(app).get("/loan/export.csv").buffer(true).parse(asText);
        expect(res.status).toBe(200);
        const rows = parseCsv(String(res.body)).filter((r) => r.length > 1 || r[0] !== "");
        expect(rows).toHaveLength(1);
        expect(rows[0].join(",")).toBe(HEADER);
    });

    it("AC7 the grid page links to the export", async () => {
        vi.mocked(readLoans).mockReturnValue([]);
        const res = await request(app).get("/loan");
        expect(res.status).toBe(200);
        expect(res.text).toMatch(/href="\/loan\/export\.csv"/);
        expect(res.text).toMatch(/Export CSV/i);
    });

    it("scope: existing routes still work", async () => {
        vi.mocked(readLoans).mockReturnValue(LOANS);
        const res = await request(app).get("/loan/api/loans");
        expect(res.status).toBe(200);
        expect(res.body.loans).toHaveLength(2);
    });
});
