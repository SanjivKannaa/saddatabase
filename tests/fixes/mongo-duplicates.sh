mongosh --quiet app --eval '
const dups = db.users.aggregate([{ $sort: { updatedAt: -1 } }, { $group: { _id: { $toLower: "$email" }, ids: { $push: "$_id" }, n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }]).toArray();
dups.forEach(d => db.users.deleteMany({ _id: { $in: d.ids.slice(1) } }));
db.users.createIndex({ email: 1 }, { unique: true, collation: { locale: "en", strength: 2 } })'
