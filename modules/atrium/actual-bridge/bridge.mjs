// JSON bridge to Actual Budget: `bridge.mjs <command>` reads JSON args on stdin, writes one JSON document on stdout.
import * as api from "@actual-app/api";
import { mkdirSync } from "node:fs";

// The api library logs to stdout; stdout is reserved for the result.
console.log = (...args) => console.error(...args);

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

async function readArgs() {
  let text = "";
  for await (const chunk of process.stdin) text += chunk;
  return text.trim() ? JSON.parse(text) : {};
}

function need(args, name, pattern) {
  const value = args[name];
  if (typeof value !== "string" || !pattern.test(value)) throw new Error(`${name} is missing or malformed`);
  return value;
}

const commands = {
  async accounts() {
    const accounts = await api.getAccounts();
    const out = [];
    for (const a of accounts) {
      out.push({
        id: a.id,
        name: a.name,
        offbudget: !!a.offbudget,
        closed: !!a.closed,
        balance: await api.getAccountBalance(a.id),
      });
    }
    return { accounts: out };
  },

  async categories() {
    const groups = await api.getCategoryGroups();
    return {
      groups: groups.map((g) => ({
        id: g.id,
        name: g.name,
        is_income: !!g.is_income,
        categories: (g.categories ?? []).map((c) => ({ id: c.id, name: c.name, is_income: !!c.is_income, hidden: !!c.hidden })),
      })),
    };
  },

  async transactions(args) {
    const start = need(args, "start", DATE);
    const end = need(args, "end", DATE);
    const limit = Number.isInteger(args.limit) && args.limit > 0 ? args.limit : 100;
    const accounts = args.account ? [{ id: args.account }] : await api.getAccounts();
    const payees = new Map((await api.getPayees()).map((p) => [p.id, p.name]));
    const rows = [];
    for (const a of accounts) {
      for (const t of await api.getTransactions(a.id, start, end)) {
        rows.push({
          id: t.id,
          account: t.account,
          date: t.date,
          amount: t.amount,
          payee: payees.get(t.payee) ?? t.imported_payee ?? null,
          category: t.category ?? null,
          notes: t.notes ?? null,
          transfer: !!t.transfer_id,
        });
      }
    }
    rows.sort((x, y) => (x.date < y.date ? 1 : x.date > y.date ? -1 : 0));
    return { transactions: rows.slice(0, limit), total: rows.length };
  },

  async "budget-month"(args) {
    const month = need(args, "month", MONTH);
    const m = await api.getBudgetMonth(month);
    return {
      month: m.month,
      income_available: m.incomeAvailable,
      total_budgeted: m.totalBudgeted,
      total_spent: m.totalSpent,
      to_budget: m.toBudget,
      categories: m.categoryGroups.flatMap((g) =>
        (g.categories ?? []).map((c) => ({
          id: c.id,
          name: c.name,
          group: g.name,
          budgeted: c.budgeted,
          spent: c.spent,
          balance: c.balance,
        })),
      ),
    };
  },

  async "set-category"(args) {
    const id = args.transaction_id;
    if (typeof id !== "string" || !id) throw new Error("transaction_id is required");
    const category = args.category_id ?? null;
    if (category !== null && typeof category !== "string") throw new Error("category_id must be a string or null");
    const { data } = await api.aqlQuery(api.q("transactions").filter({ id }).select(["id", "category"]));
    if (data.length !== 1) throw new Error(`transaction ${id} not found`);
    await api.updateTransaction(id, { category });
    return { transaction_id: id, previous_category: data[0].category ?? null, category_id: category };
  },
};

async function main() {
  const name = process.argv[2];
  if (!Object.hasOwn(commands, name)) throw new Error(`unknown command ${name}`);
  const args = await readArgs();
  const dataDir = required("ATRIUM_ACTUAL_DATA");
  mkdirSync(dataDir, { recursive: true });
  const password = required("ACTUAL_PASSWORD");
  const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD;
  try {
    await api.init({ dataDir, serverURL: required("ACTUAL_SERVER_URL"), password });
    await api.downloadBudget(required("ACTUAL_SYNC_ID"), encryption ? { password: encryption } : undefined);
    process.stdout.write(JSON.stringify(await commands[name](args)));
  } finally {
    await api.shutdown();
  }
}

main().catch((e) => {
  process.stderr.write(`${e?.message ?? e}\n`);
  process.exitCode = 1;
});
