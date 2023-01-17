import { useEffect, useState } from "react";
import Header from "./Header";
import { getAllActivePools } from "../utils/contracts";

export default function MarketsPage() {
  const [markets, setMarkets] = useState([]);

  useEffect(() => {
    async function test() {
      setMarkets(await getAllActivePools());
    }
    test();
  }, []);

  return (
    <>
      <Header />

      <h2>All Active Markets</h2>
      {markets.map((market, index) => (
        <p>{market}</p>
      ))}
    </>
  );
}
