import type {FastifyInstance, RouteOptions} from 'fastify';
import prisma from 'indexer-prisma';
import {HTTPStatus} from '../../utils/http';
import {isValidStarknetAddress} from '../../utils/starknet';

interface TipParams {
  deposit_id?: string;
  sender?: string;
  nostr_recipient?: string;
}

async function tipServiceRoute(fastify: FastifyInstance, options: RouteOptions) {
  // Get all tips
  fastify.get('/tips', async (request, reply) => {
    try {
      const tips = await prisma.tip_deposit.findMany({
        select: {
          deposit_id: true,
          sender: true,
          nostr_recipient: true,
          starknet_recipient: true,
          token_address: true,
          amount: true,
          gas_amount: true,
          is_claimed: true,
          is_cancelled: true,
          created_at: true,
          updated_at: true,
        },
      });

      reply.status(HTTPStatus.OK).send({
        data: tips,
      });
    } catch (error) {
      console.error('Error fetching tips:', error);
      reply.status(HTTPStatus.InternalServerError).send({ message: 'Internal server error.' });
    }
  });

  // Get tip by deposit ID
  fastify.get<{
    Params: TipParams;
  }>('/tips/:deposit_id', async (request, reply) => {
    try {
      const { deposit_id } = request.params;

      const tip = await prisma.tip_deposit.findUnique({
        where: { deposit_id },
        select: {
          deposit_id: true,
          sender: true,
          nostr_recipient: true,
          starknet_recipient: true,
          token_address: true,
          amount: true,
          gas_amount: true,
          is_claimed: true,
          is_cancelled: true,
          created_at: true,
          updated_at: true,
        },
      });

      reply.status(HTTPStatus.OK).send({
        data: tip,
      });
    } catch (error) {
      console.error('Error fetching tip:', error);
      reply.status(HTTPStatus.InternalServerError).send({ message: 'Internal server error.' });
    }
  });

  // Get tips by sender
  fastify.get<{
    Params: TipParams;
  }>('/tips/sender/:sender', async (request, reply) => {
    try {
      const { sender } = request.params;
      if (!isValidStarknetAddress(sender)) {
        reply.status(HTTPStatus.BadRequest).send({
          code: HTTPStatus.BadRequest,
          message: 'Invalid sender address',
        });
        return;
      }

      const tips = await prisma.tip_deposit.findMany({
        where: { sender },
        select: {
          deposit_id: true,
          sender: true,
          nostr_recipient: true,
          starknet_recipient: true,
          token_address: true,
          amount: true,
          gas_amount: true,
          is_claimed: true,
          is_cancelled: true,
          created_at: true,
          updated_at: true,
        },
      });

      reply.status(HTTPStatus.OK).send({
        data: tips,
      });
    } catch (error) {
      console.error('Error fetching tips by sender:', error);
      reply.status(HTTPStatus.InternalServerError).send({ message: 'Internal server error.' });
    }
  });

  // Get tips by recipient
  fastify.get<{
    Params: TipParams;
  }>('/tips/recipient/:nostr_recipient', async (request, reply) => {
    try {
      const { nostr_recipient } = request.params;
      if (!isValidStarknetAddress(nostr_recipient)) {
        reply.status(HTTPStatus.BadRequest).send({
          code: HTTPStatus.BadRequest,
          message: 'Invalid recipient address',
        });
        return;
      }

      const tips = await prisma.tip_deposit.findMany({
        where: { nostr_recipient },
        select: {
          deposit_id: true,
          sender: true,
          nostr_recipient: true,
          starknet_recipient: true,
          token_address: true,
          amount: true,
          gas_amount: true,
          gas_token_address: true,
          is_claimed: true,
          is_cancelled: true,
          created_at: true,
          updated_at: true,
        },
      });

      reply.status(HTTPStatus.OK).send({
        data: tips,
      });
    } catch (error) {
      console.error('Error fetching tips by recipient:', error);
      reply.status(HTTPStatus.InternalServerError).send({ message: 'Internal server error.' });
    }
  });
}

export default tipServiceRoute;