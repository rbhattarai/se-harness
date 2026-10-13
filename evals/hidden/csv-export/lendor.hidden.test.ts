// Hidden acceptance tests for REQ-001 (lending-webapp). See loan.hidden.test.ts.
import { describe, it, expect, vi, beforeEach } from "vitest";
import request from "supertest";

vi.mock("../src/data/approverStore", () => ({
    readApprovers: vi.fn(),
    writeApprover: vi.fn(),
    deleteApprover: vi.fn(),
    generateApproverId: vi.fn(),
    readLoans: vi.fn(),
    writeLoan: vi.fn(),
}));
vi.mock("../src/events", () => ({
    addClient: vi.fn(),
    broadcast: vi.fn(),
    notifyApp: vi.fn(),
}));

import app from "../src/app";
import { readApprovers } from "../src/data/approverStore";

const HEADER = "id,name,createdAt";

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

const APPROVERS = [
    { id: "APR-20260101-AAAA", name: "John Doe", createdAt: "2026-01-01T10:00:00.000Z" },
    { id: "APR-20260102-BBBB", name: 'Doe, "Jane"', createdAt: "2026-01-02T10:00:00.000Z" },
];

describe("hidden: GET /lendor/export.csv", () => {
    beforeEach(() => {
        vi.resetAllMocks();
    });

    it("AC3 returns 200, text/csv and an attachment filename with a date", async () => {
        vi.mocked(readApprovers).mockReturnValue(APPROVERS);
        const res = await request(app).get("/lendor/export.csv");
        expect(res.status).toBe(200);
        expect(res.headers["content-type"]).toMatch(/^text\/csv/);
        expect(res.headers["content-disposition"]).toMatch(
            /^attachment; filename="loan-approvers-\d{4}-\d{2}-\d{2}\.csv"$/,
        );
    });

    it("AC4 exact header row and one record per approver", async () => {
        vi.mocked(readApprovers).mockReturnValue(APPROVERS);
        const res = await request(app).get("/lendor/export.csv").buffer(true).parse(asText);
        const rows = parseCsv(String(res.body));
        expect(rows[0].join(",")).toBe(HEADER);
        expect(rows).toHaveLength(3);
        expect(rows[1]).toEqual(["APR-20260101-AAAA", "John Doe", "2026-01-01T10:00:00.000Z"]);
    });

    it("AC5 escapes commas and quotes (RFC 4180)", async () => {
        vi.mocked(readApprovers).mockReturnValue(APPROVERS);
        const res = await request(app).get("/lendor/export.csv").buffer(true).parse(asText);
        expect(String(res.body)).toContain('"Doe, ""Jane"""');
    });

    it("AC5 each special character on its own triggers quoting", async () => {
        const mk = (name: string) => ({ ...APPROVERS[0], name });
        vi.mocked(readApprovers).mockReturnValue([mk("a,b"), mk('a"b'), mk("a\nb"), mk("plain")]);
        const res = await request(app).get("/lendor/export.csv").buffer(true).parse(asText);
        const body = String(res.body);
        expect(body).toContain(',"a,b",');
        expect(body).toContain(',"a""b",');
        expect(body).toContain(',"a\nb",');
        expect(body).toContain(",plain,");
    });

    it("AC6 empty store -> 200 with only the header row", async () => {
        vi.mocked(readApprovers).mockReturnValue([]);
        const res = await request(app).get("/lendor/export.csv").buffer(true).parse(asText);
        expect(res.status).toBe(200);
        const rows = parseCsv(String(res.body)).filter((r) => r.length > 1 || r[0] !== "");
        expect(rows).toHaveLength(1);
        expect(rows[0].join(",")).toBe(HEADER);
    });

    it("AC7 the grid page links to the export", async () => {
        vi.mocked(readApprovers).mockReturnValue([]);
        const res = await request(app).get("/lendor");
        expect(res.status).toBe(200);
        expect(res.text).toMatch(/href="\/lendor\/export\.csv"/);
        expect(res.text).toMatch(/Export CSV/i);
    });
});
